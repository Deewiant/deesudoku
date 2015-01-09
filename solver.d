module deesudoku.solver;

import std.bitarray;
//import std.cstream : dout;
import std.math : sqrt;
version (Posix)
	import std.perf : TickCounter = PerformanceCounter;
else
	import std.perf : TickCounter;
import std.string : toString;
import
	deesudoku.defs,
	deesudoku.output;

// tentative is passed when the situation is a guess
// similarly, the return value matters only when the situation is a guess
ulong guessIterations;
bool solve(bool tentative = false) {
	bool changed;
	ulong iterations = 0;
	long time; // no see
	TickCounter timer;

	if (!tentative) {
		guessIterations = 0;

		timer = new TickCounter();
		if (someStats) {
			foreach (s; statistics.keys)
				statistics.remove(s);
			guessCount = correctGuessCount = 0;
			timer.start();
		}

		updateCandidates();

		done = false;
	}

	do {
		changed = false;

		if (showGrid)
			printGrid();

		if (showCandidates)
			printCandidates();

		if ((tentative || checkValidity) && !valid()) {
			if (tentative)
				return false;
			dout.writefln("The Sudoku appears to be invalid.");
			dout.writefln("Halting...");
			dout.flush();
			break;
		}

		if (someStats) {
			if (tentative)
				++guessIterations;
			else
				++iterations;
		}

		foreach (method; methods) {
			if (changed = method(), changed) {
				if (explain)
					dout.flush();
				break;
			}
		}

		if (solved()) {
			done = true;
			break;
		}

	} while (changed);

	if (tentative)
		return true;

	if (someStats) {
		timer.stop();
		time = timer.milliseconds();
	}

	if (!noGrid)
		printGrid();

	if (totalStats) {
		foreach (s, n; statistics)
			totalStatistics[s] += n;
		totalIterations      += iterations;
		totalTime            += time;
		totalGuesses         += guessCount;
		totalCorGuesses      += correctGuessCount;
		totalGuessIterations += guessIterations;

		if (done)
			++completed;
	}

	if (stats)
		printStats(statistics, iterations, time, guessCount, correctGuessCount, guessIterations);

	return true;
}

private int[][][] parts; // private parts, har har
void initSolver() {
	// ordered according to their likelihood of being useful
	// this increases speed (reduces iterations) somewhat
	// ichthyology is older than both xyWing and xyzWing
	methods ~= &expandSingleCandidates;
	methods ~= &assignUniques;
	methods ~= &checkConstraints;
	methods ~= &subset;
	//methods ~= &nakedSubset;
	//methods ~= &hiddenSubset;

	if (parts.length)
		return;

	int limit = dim/2;

	parts = new int[][][limit-1];
	int[] offsets = new int[dim];
	for (int i = 0; i < dim; ++i)
		offsets[i] = i;

	Parter!(int) p;
	for (int i = 2; i <= limit; ++i) {
		p = new Parter!(int)(offsets, i);
		parts[i-2] = p.all();
	}
	// in parts[i] we have all the int[]s representing array indices
	// into all partitions of size (i+2) in an array of size dim
	// so parts[0][0] are the indices of the first possible partition of size 2
	// and parts[0][$-1] are the indices of the last

	methods ~= &xyWing;
	methods	~= &xyzWing;
	methods ~= &ichthyology;

	if (guessing)
		methods ~= &guess; // hope this never gets called...
}

private:

bool function()[] methods;

// statistics mostly use the names at http://www.simes.clara.co.uk/programs/sudokutechniques.htm
ulong[char[]] statistics;
// are output a bit differently so need their own variables
ulong guessCount, correctGuessCount;

// solving
//////////

// if a cell has only a single candidate, set that cell's value to the candidate
bool expandSingleCandidates() {
	const char[] name = "Naked singles";
	bool changed;
	debug (methods) dout.writefln(name);

	foreach (c; grid) {
		if (c.candNum == 1) {
			for (int i = 0; i < dim; ++i) {
				if (c.candidates[i]) {
					c.val = i+1;
					c.candidates[i] = false;
					break;
				}
			}
			c.candNum = 0;
			changed = true;

			if (explain)
				dout.writefln("Cell %s's only candidate is %d.", c.toString, c.val);

			updateCandidatesAffectedBy(c);

			if (someStats)
				++statistics[name];
		}
	}

	return changed;
}

// if a candidate is in only one cell of a row/column/block, it must be where it is
bool assignUniques() {
	const char[] name = "Hidden singles";
	debug (methods) dout.writefln(name);

	foreach (row; rows) {
		int[int] canCount, // key is candidate value, value is number of such candidates
		         position; // key is candidate value, value is Cell's position
		                   // yes, this can get overwritten, but not if there's only one such candidate

		foreach (i, c; row) {
			for (int n = 1; n <= dim; ++n) {
				if (c.candidates[n-1]) {
					++canCount[n];
					position[n] = i;
				}
			}
		}

		foreach (i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = row[position[i]];
				for (int j = 0; j < dim; ++j)
					c.candidates[j] = false;
				c.val = i;
				c.candNum = 0;

				if (explain) {
					dout.writefln("Cell %s is the only one in row %s to have the candidate %d.",
					              c.toString,
					              getRow(c.row),
					              c.val
					);
				}

				updateCandidatesAffectedBy(c);
				if (someStats)
					++statistics[name];

				return true;
			}
		}
	}

	foreach (col; cols) {
		int[int] canCount,
		         position;

		foreach (i, c; col) {
			for (int n = 1; n <= dim; ++n) {
				if (c.candidates[n-1]) {
					++canCount[n];
					position[n] = i;
				}
			}
		}

		foreach (i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = col[position[i]];

				for (int j = 0; j < dim; ++j)
					c.candidates[j] = false;
				c.val = i;
				c.candNum = 0;

				if (explain) {
					dout.writefln("Cell %s is the only one in column %d to have the candidate %d.",
					              c.toString,
					              c.col + 1,
					              c.val
					);
				}

				updateCandidatesAffectedBy(c);
				if (someStats)
					++statistics[name];

				return true;
			}
		}
	}

	foreach (box; boxes) {
		int[int] canCount,
		         position;

		foreach (i, c; box) {
			for (int n = 1; n <= dim; ++n) {
				if (c.candidates[n-1]) {
					++canCount[n];
					position[n] = i;
				}
			}
		}

		foreach (i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = box[position[i]];
				for (int j = 0; j < dim; ++j)
					c.candidates[j] = false;
				c.val = i;
				c.candNum = 0;

				if (explain) {
					dout.writefln("Cell %s is the only one in box at %s to have the candidate %d.",
					               c.toString,
					               boxes[c.box][0].toString,
					               c.val
					);
				}

				updateCandidatesAffectedBy(c);
				if (someStats)
					++statistics[name];

				return true;
			}
		}
	}

	return false;
}

// check each row/column for candidates that occur only in a specific box
// if there are any, remove those candidates from the other cells in said box
// and the same the other way around, check each box for row/column
bool checkConstraints() {
	const char[] name = "House interactions";
	debug (methods) dout.writefln(name);

	bool rowColFunc(int r, Cell[] row, char[] str, bool col) {
		int[int] boxOf; // key is number value, value is -1 for more than one box or the box number
		int[int] nFound;

		foreach (ce; row) {
			for (int cand = 0; cand < dim; ++cand) {
				if (ce.candidates[cand]) {
					if (cand in boxOf && boxOf[cand] != ce.box)
						boxOf[cand] = -1; // oops, found it already
					else {
						boxOf[cand] = ce.box;
						++nFound[cand];
					}
				}
			}
		}

		foreach (value; boxOf.keys) {
			if (boxOf[value] != -1 && nFound[value] > 1) {
				int removed;
				foreach (cell; boxes[boxOf[value]])
					if ((col && cell.col != r) || (!col && cell.row != r))
						removed += cell.removeCandidate(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Box at %s must contain %d in %s; ",
						            boxes[boxOf[value]][0].toString,
						            value+1,
						            str
						);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value+1);
					}

					if (someStats)
						++statistics[name];

					return true;
				}
			}
		}

		return false;
	}

	foreach (r, row; rows)
		if (rowColFunc(r, row, format("row %s", getRow(r)), false))
			return true;
	foreach (c, col; cols)
		if (rowColFunc(c, col, format("column %d", c + 1), true))
			return true;

	foreach (b, box; boxes) {
		int[int] colOf, rowOf;
		int[int] nCFound, nRFound;

		foreach (ce; box) {
			for (int cand = 0; cand < dim; ++cand) {
				if (ce.candidates[cand]) {
					if (cand in colOf && colOf[cand] != ce.col)
						colOf[cand] = -1;
					else {
						colOf[cand] = ce.col;
						++nCFound[cand];
					}
				}
			}
		}

		foreach (value; colOf.keys) {
			if (colOf[value] != -1 && nCFound[value] > 1) {
				int removed;
				foreach (cell; cols[colOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidate(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Column %d must contain %d in box at %s; ",
						            colOf[value] + 1, value+1, boxes[b][0].toString);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value+1);
					}

					if (someStats)
						++statistics[name];

					return true;
				}
			}
		}

		foreach (ce; box) {
			for (int cand = 0; cand < dim; ++cand) {
				if (ce.candidates[cand]) {
					if (cand in rowOf && rowOf[cand] != ce.row)
						rowOf[cand] = -1;
					else {
						rowOf[cand] = ce.row;
						++nRFound[cand];
					}
				}
			}
		}

		foreach (value; rowOf.keys) {
			if (rowOf[value] != -1 && nRFound[value] > 1) {
				int removed;
				foreach (cell; rows[rowOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidate(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Row %s must contain %d in box at %s; ",
						            getRow(rowOf[value]), value+1, boxes[b][0].toString);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value+1);
					}

					if (someStats)
						++statistics[name];

					return true;
				}
			}
		}
	}

	return false;
}

// if n cells in the same row/column/block have altogether only n different candidates,
// can remove those candidates from the others in that row/column/block
bool nakedSubset() {
	const char[] name = "Naked subsets";
	debug (methods) dout.writefln(name);

	bool generalFunction(Cell[] area, char[] str) {

		// see http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
		// (number of empty cells in area) / 2
		int nakedLimit = 0;
		foreach (cell; area)
			if (cell.val == EMPTY)
				++nakedLimit;
		nakedLimit /= 2;

		if (nakedLimit < 2)
			return false;

		Cell[] cells = new Cell[nakedLimit];

		foreach (cell; area) {

			static bool recurse(Cell[] area, Cell[] allCells, int cellCount, int candCount, BitArray candidates, char[] str) {
				Cell[] cells = allCells[0..cellCount];

				if (cells.length < candCount) {
					foreach (c; area) {
						if (cells.contains(c))
							continue;

						if (c.candNum > 0) {
							// can't use c if it adds too many candidates

							BitArray newCands = candidates | c.candidates;
							candCount = bitCount(newCands);

							// allCells.length being equal to nakedLimit
							if (candCount > allCells.length)
								continue;

							allCells[cellCount] = c;
							if (recurse(area, allCells, cellCount+1, candCount, newCands, str))
								return true;
						}
					}
				} else if (cells.length == candCount) {
					int removed;

					eachcell: foreach (c; area) {
						foreach (found; cells)
							if (c is found)
								continue eachcell;

						removed += c.removeCandidates(candidates);
					}

					if (removed > 0) {
						if (explain) {
							char[] cellList, candList;
							foreach (c; cells.sort)
								cellList ~= format("%s, ", c.toString);
							for (int i = 0; i < dim; ++i)
								if (candidates[i])
									candList ~= format("%d, ", i+1);

							dout.writef("Cells %s must contain %s; ",
							            // shave off the extra ", "s
							            cellList[0..$-2],
							            candList[0..$-2]
							);

							dout.writefln("eliminated %s in %s.", nCandidates(removed, "such"), str);
						}

						if (someStats) switch (candCount) {
							case 2:	 ++statistics["Naked pairs"];       break;
							case 3:  ++statistics["Naked triplets"];    break;
							case 4:  ++statistics["Naked quadruplets"]; break;
							default: ++statistics[format("Naked subsets (n=%d)", candCount)];
						}

						return true;
					}
				}

				return false;
			}

			if (cell.candNum > 1 && cell.candNum <= nakedLimit) {
				cells[0] = cell;
				if (recurse(area, cells, 1, cell.candNum, cell.candidates.dup, str))
					return true;
			}
		}

		return false;
	}

	foreach (i, row; rows)
		if (generalFunction(row, format("row ", getRow(i))))
			return true;
	foreach (i, col; cols)
		if (generalFunction(col, format("column ", i + 1)))
			return true;
	foreach (box; boxes)
		if (generalFunction(box, format("box at ", box[0].toString)))
			return true;
	return false;
}

// hidden subsets:
// http://www.simes.clara.co.uk/programs/sudokutechnique9.htm puts it concisely:
// If there are N cells with N candidates between them that don't appear
// elsewhere in the same row, column or block, then any other candidates
// for those cells can be eliminated.
bool hiddenSubset() {
	const char[] name = "Hidden subsets";
	debug (methods) dout.writefln(name);

	bool generalFunction(Cell[] area) {

		// see http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
		// (number of empty cells in area - 1) / 2
		int hiddenLimit = -1;
		foreach (cell; area)
			if (cell.val == EMPTY)
				++hiddenLimit;
		hiddenLimit /= 2;

		if (hiddenLimit < 2)
			return false;

		// for each possible value, each Cell in area which has that value
		Cell[][] each = new Cell[][dim];

		int[] candCounts = new int[dim];

		for (int val = 0; val < dim; ++val) {
			each[val].length = dim;
			foreach (c; area)
				if (c.candidates[val])
					each[val][candCounts[val]++] = c;
		}

		for (int n = 2; n <= hiddenLimit; ++n) {
			Cell[][] found = each.dup;

			// if I were smart this could be optimised
			// so that we put into found only those Cell[]s which have 0 < i[val] <= n
			// but then we'd need a different method of figuring out the candidates in
			// question, below
			// and I can't (be bothered to) think of a smart method of doing this
			int upToNCands = 0;
			for (int val = 0; val < dim; ++val) {
				if (candCounts[val] <= n) {
					found[val].length = candCounts[val];
					++upToNCands;
				} else
					found[val].length = 0;
			}

			// now found[x] is all the Cells in area with candidate x+1
			// unless there were more than n such Cells, in which case
			// they couldn't be part of a subset of size n

			// if there weren't enough Cells with up to n candidates no such
			// hidden subset can exist
			if (upToNCands < n)
				continue;

			Cell[][] subFound = new Cell[][n];
			eachpart: foreach (part; parts[n-2]) {
				foreach (i, p; part)
					subFound[i] = found[p];

				// so what we have in subFound are n Cell[]s
				// each of which are all the Cells in area for a certain candidate

				// make sure that there are only n different Cells altogether
				// and figure out which candidates we're looking at

				Cell[] cells = new Cell[n];
				bit[Cell] checked;
				BitArray vals;
				vals.length = dim;
				int j, h;
				foreach (inSub; subFound) {
					if (!inSub.length)
						continue eachpart;
					foreach (c; inSub) {
						if (!(c in checked)) {
							if (h >= n) // oops, too many different cells
								continue eachpart;

							cells[h++] = c;
							checked[c] = true;
						}
					}

					// figure out the candidates
					for (int k = 0; k < dim; ++k) {
						if (inSub is found[k] && !vals[k]) {
							if (j >= n) // oops, too many different candidates
								continue eachpart;

							vals[k] = true;
						}
					}
				}

				// OK, we have a hidden subset
				// remove all other candidates from each Cell in cells
				if (explain)
					cells.sort;

				int removed;
				char[] cellList;
				foreach (c; cells) {
					removed += c.removeCandidatesExcept(vals);
					if (explain)
						cellList ~= format("%s, ", c.toString);
				}

				if (removed > 0) {
					if (explain) {
						char[] candList;
						for (int k = 0; k < dim; ++k)
							if (vals[k])
								candList ~= format("%d, ", k+1);

						dout.writef("Cells %s must contain %s; ",
						            // shave off the extra ", "s
						            cellList[0..$-2],
						            candList[0..$-2]
						);

						dout.writefln("eliminated %d other candidates from them.", removed);
					}

					if (someStats) switch (n) {
						case 2:	++statistics["Hidden pairs"];       break;
						case 3: ++statistics["Hidden triplets"];    break;
						case 4: ++statistics["Hidden quadruplets"]; break;
						default: ++statistics[format("%s (n=%d)", name, n)];
					}

					return true;
				}
			}
		}

		return false;
	}

	foreach (row; rows)
		if (generalFunction(row))
			return true;
	foreach (col; cols)
		if (generalFunction(col))
			return true;
	foreach (box; boxes)
		if (generalFunction(box))
			return true;

	return false;
}

bool subset() {
	debug (methods) dout.writefln("Disjoint subsets");

	static bool generalFunction(Cell[] area, char[] areaString) {

		// see http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
		int nakedLimit = 0;
		foreach (cell; area)
			if (cell.val == EMPTY)
				++nakedLimit;
		int hiddenLimit = (nakedLimit - 1) / 2;
		nakedLimit /= 2;

		static bool subsetCheck(Cell[] area, char[] areaString, int size, bool onlyNaked = false)
		in {
			assert (area && area.length == dim);
			assert (areaString && areaString.length);
			assert (size >= 2);
		} body {
			Cell[] cells = new Cell[size];

			nextPart: foreach (partition; parts[size-2]) {

				BitArray cellCands;
				cellCands.length = dim;
				{int i = 0;
				foreach (idx; partition) {
					assert (idx < area.length);

					cells[i++] = area[idx];
					cellCands |= area[idx].candidates;

					if (area[idx].val != EMPTY)
						continue nextPart;
				}}

				// so cells is now some Cells which could be a subset

				static bool hiddenSubset(Cell[] area, Cell[] cells, BitArray cellCands) {
					BitArray otherCands;
					otherCands.length = cellCands.length;

					foreach (cell; area)
						if (!cells.contains(cell))
							otherCands |= cell.candidates;

					BitArray keepCands = cellCands & ~otherCands;
					if (bitCount(keepCands) == cells.length) {
						// we have a hidden subset in cells
						// remove all other candidates from cells

						if (explain)
							cells.sort;

						int removed = 0;
						char[] cellList;
						foreach (cell; cells) {
							removed += cell.removeCandidatesExcept(keepCands);
							if (explain)
								cellList ~= cell.toString ~ ", ";
						}

						if (removed > 0) {
							if (explain) {
								char[] candList;
								foreach (i, cand; keepCands)
									if (cand)
										candList ~= toString(i+1) ~ ", ";

								dout.writef("Cells %s must contain %s; ",
								            // shave off the extra ", "s
								            cellList[0..$-2],
								            candList[0..$-2]
								);

								dout.writefln("eliminated %s from them.", nCandidates(removed, "other"));
							}

							if (someStats) switch (cells.length) {
								case 2:	 ++statistics["Hidden pairs"];       break;
								case 3:  ++statistics["Hidden triplets"];    break;
								case 4:  ++statistics["Hidden quadruplets"]; break;
								default: ++statistics["Hidden subsets (n="~toString(cells.length)~")"];
							}

							return true;
						}
					}

					return false;
				}

				static bool nakedSubset(Cell[] area, char[] areaString, Cell[] cells, BitArray cellCands) {
					if (bitCount(cellCands) == cells.length) {
						// we have a naked subset in cells
						// remove cellCands from all other Cells in area

						int removed = 0;
						foreach (cell; area)
							if (!cells.contains(cell))
								removed += cell.removeCandidates(cellCands);

						if (removed > 0) {
							if (explain) {
								char[] cellList, candList;

								foreach (cell; cells.sort)
									cellList ~= cell.toString ~ ", ";

								foreach (i, cand; cellCands)
									if (cand)
										candList ~= toString(i+1) ~ ", ";

								dout.writef("Cells %s must contain %s; ",
							            // shave off the extra ", "s
							            cellList[0..$-2],
							            candList[0..$-2]
								);

								dout.writefln("eliminated %s in %s.", nCandidates(removed, "such"), areaString);
							}

							if (someStats) switch (cells.length) {
								case 2:	 ++statistics["Naked pairs"];       break;
								case 3:  ++statistics["Naked triplets"];    break;
								case 4:  ++statistics["Naked quadruplets"]; break;
								default: ++statistics["Naked subsets (n="~toString(cells.length)~")"];
							}

							return true;
						}
					}

					return false;
				}

				if (!onlyNaked && hiddenSubset(area, cells, cellCands))
					return true;

				if (nakedSubset(area, areaString, cells, cellCands))
					return true;
			}

			return false;
		}

		for (int sz = 2; sz <= hiddenLimit; ++sz)
			if (subsetCheck(area, areaString, sz))
				return true;

		if (nakedLimit >= 2 && nakedLimit != hiddenLimit) {
			assert (nakedLimit > hiddenLimit);

			if (subsetCheck(area, areaString, nakedLimit, true))
				return true;
		}

		return false;
	}

	foreach (i, row; rows)
		if (generalFunction(row, "row " ~ getRow(i)))
			return true;
	foreach (i, col; cols)
		if (generalFunction(col, "column " ~ toString(i + 1)))
			return true;
	foreach (i, box; boxes)
		if (generalFunction(box, "box " ~ toString(i + 1)))
			return true;

	return false;
}

// most understandable general definition I found:
// http://www.setbb.com/phpbb/viewtopic.php?t=240&mforum=sudoku
/+
Look for N columns (2 for X-wing, 3 for the Swordfish, 4 for a Jellyfish, 5 for a Squirmbag) with 2 to N candidate cells for ONE given digit. If these fall on exactly N common rows, then all N rows can be cleared of that digit (except in the defining cells!). The test can also be done swapping rows for columns.
+/
// cheers to MadOverlord there for getting the idea of a 9x9 fish being called a Cthulhu
bool ichthyology() {
	const char[] name = "Ichthyology";
	debug (methods) dout.writefln(name);

	// a fish can be at most of size dim/2
	// since fish of size n in rows is a fish of size dim-n in cols
	for (int n = 2, limit = dim/2; n <= limit; ++n) {

		// the parameter is called rows and cols even though they may be cols and rows, respectively
		// because it's easier to talk about rows and cols than areas and otherAreas or some such
		// it makes both the comments and the code clearer
		static bool generalFunction(int n, Cell[][] rows, Cell[][] cols, int delegate(Cell) getCol, int delegate(Cell) getRow, char[] delegate(int) colString) {

			for (int val = 0; val < dim; ++val) {
				Cell[][] found = new Cell[][dim];

				{int f = 0;
				foreach (i, row; rows) {
					Cell[] cs = new Cell[dim];
					int s = 0;

					// put the candidate cells from row to cs
					foreach (c; row)
						if (c.candidates[val])
							cs[s++] = c;

					if (s >= 2 && s <= n) {
						cs.length = s;
						found[f++] = cs.dup;
					}
				}found.length = f;}

				// so now found contains all the rows with 2 to n candidates for val
				// so we need to look at every partition of size n of found

				Cell[][] subFound = new Cell[][n];

				nextPart: foreach (partition; parts[n-2]) {

					{int i = 0;
					foreach (idx; partition) {
						if (idx >= found.length)
							continue nextPart;
						subFound[i++] = found[idx];
					}
					assert (i == n);}

					// count the number of different columns in the partition
					// and make sure they add up to n
					// this could be done in the above loop, so that we wouldn't need
					// subFound at all, but that's actually much slower, since now we
					// can continue nextPart before doing this at all --- with the other
					// method we'd do this dozens of times only to ignore the results
					int number = 0;
					bool[int] seenCols, foundRows;
					char[] cellList;

					foreach (row; subFound) {
						foreach (c; row) {
							if (explain)
								cellList ~= format("%s, ", c.toString);

							if (!(getCol(c) in seenCols)) {
								seenCols[getCol(c)] = true;
								++number;
							}
						}

						foundRows[getRow(row[0])] = true;
					}

					if (number != n)
						continue;

					// if got this far, can remove the candidates for val from all seen cols
					// except from those cells whose row was found - they're the intersection points
					int removed = 0;
					char[] colList;

					foreach (i; seenCols.keys) {
						if (explain)
							colList ~= colString(i) ~ ", ";
						foreach (c; cols[i])
							if (!(getRow(c) in foundRows))
								removed += c.removeCandidate(val);
					}

					if (removed > 0) {
						char[] specificName;
						switch (n) {
							case 2: specificName = "X-wing";    break;
							case 3: specificName = "Swordfish"; break;
							case 4: specificName = "Jellyfish"; break;
							case 5: specificName = "Squirmbag"; break;
							case 9: specificName = "Cthulhu";   break;
							default: specificName = "Fish";
						}

						if (explain) {
							dout.writef(
								"Found a%s %s among %s for %d; ",
								(n == 2 ? "n" : ""), specificName,
								cellList[0..$-2],
								val+1
							);

							dout.writefln(
								"eliminated %s for %d in columns %s.",
								nCandidates(removed), val+1, colList[0..$-2]
							);
						}

						if (someStats) {
							if (n == 2 || n == 5 || n == 9)
								++statistics[specificName ~ 's'];
							else if (n == 3 || n == 4)
								++statistics[specificName];
							else
								++statistics[format("%s (n=%d)", name, n)];
						}

						return true;
					}
				}
			}

			return false;
		}

		// rows first
		if (generalFunction(n, rows, cols, (Cell c){return c.col;}, (Cell c){return c.row;}, (int i){return toString(i + 1);}) ||
		    generalFunction(n, cols, rows, (Cell c){return c.row;}, (Cell c){return c.col;}, (int i){return .getRow(i);     })
		)
			return true;

		// columns now...
		/+for (int val = 0; val < dim; ++val) {
			Cell[][] found = new Cell[][dim];

			{int f = 0;
			foreach (i, col; cols) {
				Cell[] cs = new Cell[dim];
				int s;

				// get the candidate cells in cs
				foreach (c; col)
					if (c.candidates[val])
						cs[s++] = c;

				if (s>= 2 && s <= n) {
					cs.length = s;
					found[f++] = cs.dup;
				}
			}found.length = f;}

			Cell[][] subFound = new Cell[][n];

			nextPart2: foreach (partition; parts[n-2]) {
				{int i = 0;
				foreach (idx; partition) {
					if (idx >= found.length)
						continue nextPart2;
					subFound[i++] = found[idx];
				}
				assert (i == n);}

				int number;
				bool[int] seenRows, foundCols;
				char[] cellList;
				foreach (col; subFound) {
					foreach (c; col) {
						if (explain)
							cellList ~= format("%s, ", c.toString);

						if (!(c.row in seenRows)) {
							seenRows[c.row] = true;
							++number;
						}
					}

					foundCols[col[0].col] = true;
				}

				if (number != n)
					continue;

				int removed;
				char[] rowList;
				foreach (i; seenRows.keys) {
					if (explain)
						rowList ~= format("%s, ", getRow(i));
					foreach (c; rows[i]) {
						if (!(c.col in foundCols))
							removed += c.removeCandidate(val);
					}
				}

				if (removed > 0) {
					char[] specificName;
					switch (n) {
						case 2: specificName = "X-wing";    break;
						case 3: specificName = "Swordfish"; break;
						case 4: specificName = "Jellyfish"; break;
						case 5: specificName = "Squirmbag"; break;
						case 9: specificName = "Cthulhu";   break;
						default: specificName = "Fish";
					}

					if (explain) {
						dout.writef(
							"Found a%s %s among %s for %d; ",
							(n == 2 ? "n" : ""), specificName,
							cellList[0..$-2],
							val+1
						);

						dout.writefln(
							"eliminated %s for %d in rows %s.",
							nCandidates(removed), val+1, rowList[0..$-2]
						);
					}

					if (someStats) {
						if (n == 2 || n == 5 || n == 9)
							++statistics[specificName ~ 's'];
						else if (n == 3 || n == 4)
							++statistics[specificName];
						else
							++statistics[format("%s (n=%d)", name, n)];
					}

					return true;
				}
			}
		}+/
	}

	return false;
}

// Find a cell with two candidates, X and Y.
// Find two buddies of that cell with candidates X and Z, Y and Z.
// Then can remove Z from the candidates of all cells that are buddies with both of the two buddies.
bool xyWing() {
	const char[] name = "XY-wing";
	debug (methods) dout.writefln(name);

	foreach (c; grid) {
		if (c.candNum != 2)
			continue;

		int X = -1, Y = -1;
		for (int i = 0; i < dim; ++i) {
			if (c.candidates[i]) {
				if (X == -1)
					X = i;
				else if (Y == -1) {
					Y = i;
					break;
				}
			}
		}

		int[] Z;
		Cell[][] goodGroups;
		goodGroups.length = dim;

		Cell[] cBuddies = c.buddies;
		// find all buddies of c with candidates X and Z.
		// add each one to its own Cell[] in goodGroups.
		// then loop through each Z
		// and find all buddies of c with candidates Y and that Z, and each to the corresponding goodGroup.
		int i;
		foreach (friend; cBuddies) {
			if (friend.candNum != 2)
				continue;

			int firstCand = -1, secondCand = -1;
			for (int j = 0; j < dim; ++j) {
				if (friend.candidates[j]) {
					if (firstCand == -1)
						firstCand = j;
					else if (secondCand == -1) {
						secondCand = j;
						break;
					}
				}
			}

			// one of the candidates is also in c (i.e. is X or Y), other is not
			// being sneaky here... if the Z is negative, the other candidate was Y, else it was X
			if (firstCand == X && secondCand != Y) {
				Z ~= secondCand;
				goodGroups[i++] ~= friend;
			} else if (firstCand == Y && secondCand != X) {
				Z ~= -secondCand;
				goodGroups[i++] ~= friend;
			} else if (secondCand == X && firstCand != Y) {
				Z ~= firstCand;
				goodGroups[i++] ~= friend;
			} else if (secondCand == Y && firstCand != X) {
				Z ~= -firstCand;
				goodGroups[i++] ~= friend;
			}
		}
		goodGroups.length = i;

		foreach (j, inout z; Z) {
			bool otherIsX = true;
			if (z < 0) {
				z = -z;
				otherIsX = false;
			}

			foreach (friend; cBuddies) {
				if (friend.candNum != 2 || !friend.candidates[z])
					continue;

				if (otherIsX && friend.candidates[Y])
					goodGroups[j] ~= friend;
				else if (!otherIsX && friend.candidates[X])
					goodGroups[j] ~= friend;
			}
		}

		foreach (j, goodGroup; goodGroups) {
			if (!goodGroup.length)
				continue;

			auto p = new Parter!(Cell)(goodGroup, 2);
			Cell[] goodPair;
			while ((goodPair = p.next()) !is null) {
				if (goodPair[0].candidates == goodPair[1].candidates)
					continue;

				int removed;
				foreach (target; goodPair[0].buddies)
					if (target !is c && target !is goodPair[1] && areBuddies(target, goodPair[1]))
						removed += target.removeCandidate(Z[j]);

				if (removed > 0) {
					if (explain) {
						dout.writef(
							"Found an %s among %s for %d; ",
							name,
							format("%s, %s, %s", c, goodPair[0], goodPair[1]),
							Z[j]+1
						);

						dout.writefln(
							"eliminated %s for %d.",
							nCandidates(removed), Z[j]+1
						);
					}

					if (someStats)
						++statistics[name ~ 's'];

					return true;
				}
			}
		}
	}

	return false;
}

// When a cell with candidates XYZ has 2 buddies with candidates XZ and YZ, Z can be removed as a candidate from any cell that has all 3 of these cells as a buddy.
// XZ must be in same box as XYZ, YZ must be in same row/column as XYZ
// and if all three are in same box, it was a naked triple
// the only cells that have all 3 of those cells as a buddy are along the line from XYZ to YZ (can be on the other side of XYZ)
bool xyzWing() {
	const char[] name = "XYZ-wing";
	debug (methods) dout.writefln(name);

	foreach (XYZ; grid) {
		if (XYZ.candNum != 3)
			continue;

		int firstCand  = -1,
		    secondCand = -1,
		    thirdCand  = -1;
		for (int i = 0; i < dim; ++i) {
			if (XYZ.candidates[i]) {
				if (firstCand == -1)
					firstCand = i;
				else if (secondCand == -1)
					secondCand = i;
				else if (thirdCand == -1) {
					thirdCand = i;
					break;
				}
			}
		}

		Cell[] XZs;
		int[2][] shared; // i.e. the X and Z candidates
		XZs.length = shared.length = dim - 1;
		int i;
		foreach (XZ; boxes[XYZ.box]) {
			if (XZ.candNum != 2 || !contains(XYZ.candidates, XZ.candidates))
				continue;

			int XZFirst = -1, XZSecond = -1;
			for (int j = 0; j < dim; ++j) {
				if (XZ.candidates[j]) {
					if (XZFirst == -1)
						XZFirst = j;
					else if (XZSecond == -1) {
						XZSecond = j;
						break;
					}
				}
			}

			if (XZFirst == firstCand) {
				XZs[i] = XZ;
				shared[i][0] = firstCand;
				if (XZSecond == secondCand)
					shared[i++][1] = secondCand;
				else // (XZSecond == thirdCand)
					shared[i++][1] = thirdCand;
			} else if (XZFirst == secondCand) {
				// (XZSecond == thirdCand)
				XZs[i] = XZ;
				shared[i][0] = secondCand;
				shared[i++][1] = thirdCand;
			}
			// there are no other cases since both candidates are sorted
			// and XZ.candidates must be in XYZ.candidates
		}
		XZs.length = shared.length = i;

		// now we have the XZs as well as the Xs and Zs
		// so we need the YZs

		Cell[] YZs = rows[XYZ.row] ~ cols[XYZ.col];
		foreach (YZ; YZs) {
			if (YZ.candNum != 2 || !contains(XYZ.candidates, YZ.candidates) || YZ.box == XYZ.box)
				continue;

			foreach (i, XZ; XZs) {
				if (YZ.candidates == XZ.candidates)
					continue;

				// so it's a YZ
				// but what's the Z?
				// it must be in shared[i] as well as in YZ
				// and there can be only one such one, or the above if would've been true

				int Z = shared[i][0];
				if (YZ.candidates[shared[i][1]])
					Z = shared[i][1];

				// yay, proceed with removal
				int removed;
				Cell[] loopThru = YZ.row == XYZ.row ? rows[XYZ.row] : cols[XYZ.col];

				foreach (c; loopThru)
					if (c.box == XYZ.box && c !is XYZ && c !is XZ)
						removed += c.removeCandidate(Z);

				if (removed > 0) {
					if (explain) {
						dout.writef(
							"Found an %s among %s for %d; ",
							name,
							format("%s, %s, %s", XYZ, XZ, YZ),
							Z+1
						);

						dout.writefln(
							"eliminated %s for %d.",
							nCandidates(removed), Z+1
						);
					}

					if (someStats)
						++statistics[name ~ 's'];

					return true;
				}
			}
		}
	}

	return false;
}

bool guess() {
	debug (methods) dout.writefln("Guess");

	int[]      backupVals = new int     [grid.length],
	           backupCNms = new int     [grid.length];
	BitArray[] backupCans = new BitArray[grid.length];
	foreach (j, c; grid) {
		backupVals[j] = c.val;
		backupCNms[j] = c.candNum;
		backupCans[j] = c.candidates.dup;
	}

	// check small numbers of candidates first - quite a noticeable optimisation
	for (int cands = 2; cands <= dim; ++cands) foreach (i, inout cell; grid) {

		if (cell.candNum != cands)
			continue;

		for (int n = 0; n < dim; ++n) if (cell.candidates[n]) {
			cell.val = n+1;
			cell.candNum = 0;
			for (int j = 0; j < dim; ++j)
				cell.candidates[j] = false;
			updateCandidatesAffectedBy(cell);

			if (explain)
				dout.writefln("Guessing %d at %s...", n+1, cell.toString);

			if (someStats)
				++guessCount;

			if (solve(true)) {
				if (explain)
					dout.writefln("Guessing %d at %s succeeded.", n+1, cell.toString);
				
				if (someStats)
					++correctGuessCount;

				return true;
			} else {
				if (explain)
					dout.writefln("Guessing %d at %s failed, so it cannot have that value.", n+1, cell.toString);

				foreach (j, c; grid) {
					c.val        = backupVals[j];
					c.candNum    = backupCNms[j];
					c.candidates = backupCans[j].dup;
				}
				// can't use cell - it points to the old grid
				grid[i].removeCandidate(n);

				return true;
			}
		}
	}

	// we are this far only if there was a previous guess, under which we are guessing further
	// otherwise this would indicate an invalid puzzle which would have been caught by valid() earlier
	return false;
}

// utility
//////////

package void updateCandidates() {
	foreach (cell; grid)
		updateCandidates(cell);
}

void updateCandidates(Cell cell) {
	BitArray impossible; impossible.length = dim;

	foreach (c; rows [cell.row])
		if (c.val && !impossible[c.val-1])
			impossible[c.val-1] = true;

	foreach (c; cols [cell.col])
		if (c.val && !impossible[c.val-1])
			impossible[c.val-1] = true;

	foreach (c; boxes[cell.box])
		if (c.val && !impossible[c.val-1])
			impossible[c.val-1] = true;

	cell.removeCandidates(impossible);
}

void updateCandidatesAffectedBy(Cell cell) {
	foreach (c; rows [cell.row])
		if (cell !is c)
			updateCandidates(c);
	foreach (c; cols [cell.col])
		if (cell !is c)
			updateCandidates(c);
	foreach (c; boxes[cell.box])
		if (cell !is c)
			updateCandidates(c);
}

bool areBuddies(Cell a, Cell[] b...) {
	foreach (c; b)
		if (a.row != c.row && a.col != c.col && a.box != c.box)
			return false;

	return true;
}

bool valid() {
	// no values available for a location
	foreach (cell; grid)
		if (cell.candNum == 0 && cell.val == NONE)
			return false;

	bool areaCheck(Cell[] area) {
		bit[int] found, foundCandidate;

		foreach (cell; area) {
			// some value twice in this area
			if (cell.val != NONE && cell.val in found)
				return false;

			for (int i = 0; i < dim; ++i)
				if (cell.candidates[i])
					foundCandidate[i+1] = true;

			found[cell.val] = true;
		}

		// no candidates or values for a value in this area
		for (int i = 1; i <= dim; ++i)
			if (!(i in found || i in foundCandidate))
				return false;

		return true;
	}

	foreach (row; rows)
		if (!areaCheck(row))
			return false;
	foreach (col; cols)
		if (!areaCheck(col))
			return false;
	foreach (box; boxes)
		if (!areaCheck(box))
			return false;

	return true;
}

// note that this does not test for validity
bool solved() {
	foreach (cell; grid)
		if (cell.val == NONE)
			return false;

	return true;
}

// Dancing Links - thanks to Donald E. Knuth
////////////////

// implementation pending...
void dancingLinks() {
	// rows    = number of digits * number of cells
	// columns = number of rows * number of columns +
	//           number of digits * number of rows +
	//           number of digits * number of columns +
	//           number of digits * number of boxes
	// which neatly simplifies to the below.
	/+Matrix dlx = new Matrix(
		dim * dim * dim,
		dim * dim * 4
	);+/
}
