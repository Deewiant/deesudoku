module sudoku.solver;

private import
	std.cstream,
	std.math,
	std.string,
	sudoku.defs;

int prettyPrintInterval;
bool done;

void solve() {
	charWidth = cast(int)ceil(log9(dim));

	bool changed;

	if (someStats)
		foreach (char[] s; statistics.keys)
			statistics.remove(s);

	updateCandidates();

	done = false;

	do {
		changed = false;

		if (showGrid)
			printGrid();

		if (showCandidates)
			printCandidates();

		if (checkValidity && !valid()) {
			dout.writefln("The Sudoku appears to be invalid.");
			dout.writefln("Halting...");
			break;
		}

		foreach (bool function() method; methods)
			if (changed = method(), changed)
				break;

		if (someStats)
			++iterations;

		if (explain || stats)
			dout.flush();
	} while (changed);

	if (solved())
		done = true;

	// if showGrid is on, it was already printed
	if (!showGrid && !noGrid)
		printGrid();

	if (totalStats) {
		foreach (char[] s, ulong n; statistics)
			totalStatistics[s] += n;
		totalIterations += iterations;

		if (done)
			++completed;
	}

	if (stats)
		printStats(statistics, iterations);
}

private:

const bool function()[] methods;
// statistics mostly use the names at http://www.krazydad.com/blog/2005/09/29/an-index-of-sudoku-strategies/
ulong[char[]] statistics;
ulong iterations;

static this() {
	methods ~= &expandSingleCandidates;
	methods ~= &assignUniques;
	methods ~= &checkConstraints;
	methods ~= &nakedSubset;
	methods ~= &hiddenSubset;
	methods ~= &ichthyology;
}

// solving
//////////

// if a cell has only a single candidate, set that cell's value to the candidate
bool expandSingleCandidates() {
	const char[] name = "Naked singles";
	bool changed;

	foreach (inout Cell c; grid) {
		if (c.candidates.length == 1) {
			c.val = c.candidates[0];
			c.candidates.length = 0;
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
	bool changed;

	foreach (inout Cell[] row; rows) {
		int[int] canCount, // key is candidate value, value is number of such candidates
		         position; // key is candidate value, value is Cell's position
		                   // yes, this can get overwritten, but not if there's only one such candidate

		foreach (int i, Cell c; row) {
			foreach (int n; c.candidates) {
				++canCount[n];
				position[n] = i;
			}
		}

		foreach (int i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = row[position[i]];
				c.val = i;
				c.candidates.length = 0;
				changed = true;

				if (explain) {
					dout.writefln("Cell %s is the only one in row %s to have the candidate %d.",
					              c.toString,
					              ROWCHAR[c.row],
					              c.val
					);
				}

				updateCandidatesAffectedBy(c);
				if (someStats)
					++statistics[name];
			}
		}
	}

	foreach (inout Cell[] col; cols) {
		int[int] canCount,
		         position;

		foreach (int i, Cell c; col) {
			foreach (int n; c.candidates) {
				++canCount[n];
				position[n] = i;
			}
		}

		foreach (int i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = col[position[i]];
				c.val = i;
				c.candidates.length = 0;
				changed = true;

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
			}
		}
	}

	foreach (inout Cell[] box; boxes) {
		int[int] canCount,
		         position;

		foreach (int i, Cell c; box) {
			foreach (int n; c.candidates) {
				++canCount[n];
				position[n] = i;
			}
		}

		foreach (int i; canCount.keys) {
			if (canCount[i] == 1) {
				Cell c = box[position[i]];
				c.val = i;
				c.candidates.length = 0;
				changed = true;

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
			}
		}
	}

	return changed;
}

// check each row/column for candidates that occur only in a specific box
// if there are any, remove those candidates from the other cells in said box
// and the same the other way around, check each box for row/column
bool checkConstraints() {
	const char[] name = "House interactions";
	bool changed;

	void rowColFunc(int r, Cell[] row, char[] str, bool col) {
		int[int] boxOf; // key is number value, value is -1 for more than one box or the box number
		int[int] nFound;

		foreach (Cell ce; row) {
			foreach (int cand; ce.candidates) {
				if (cand in boxOf && boxOf[cand] != ce.box)
					boxOf[cand] = -1; // oops, found it already
				else {
					boxOf[cand] = ce.box;
					++nFound[cand];
				}
			}
		}

		foreach (int value; boxOf.keys) {
			if (boxOf[value] != -1 && nFound[value] > 1) {
				int removed;
				foreach (inout Cell cell; boxes[boxOf[value]])
					if ((col && cell.col != r) || (!col && cell.row != r))
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Box at %s must contain %d in %s; ",
						            boxes[boxOf[value]][0].toString,
						            value,
						            str
						);
						dout.writefln("eliminated %d candidates for %d.", removed, value);
					}
					changed = true;
					if (someStats)
						++statistics[name];
				}
			}
		}
	}

	foreach (int r, Cell[] row; rows) {
		rowColFunc(r, row, format("row %s", ROWCHAR[r]), false);

		if (changed)
			return changed;
	}
	foreach (int c, Cell[] col; cols) {
		rowColFunc(c, col, format("column %d", c + 1), true);

		if (changed)
			return changed;
	}

	foreach (int b, Cell[] box; boxes) {
		int[int] colOf, rowOf;
		int[int] nCFound, nRFound;

		foreach (Cell ce; box) {
			foreach (int cand; ce.candidates) {
				if (cand in colOf && colOf[cand] != ce.col)
					colOf[cand] = -1;
				else {
					colOf[cand] = ce.col;
					++nCFound[cand];
				}
			}
		}

		foreach (int value; colOf.keys) {
			if (colOf[value] != -1 && nCFound[value] > 1) {
				int removed;
				foreach (inout Cell cell; cols[colOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Column %d must contain %d in box at %s; ",
						            colOf[value] + 1, value, boxes[b][0].toString);
						dout.writefln("eliminated %d candidates for %d.", removed, value);
					}
					changed = true;
					if (someStats)
						++statistics[name];
				}
			}
		}

		foreach (Cell ce; box) {
			foreach (int cand; ce.candidates) {
				if (cand in rowOf && rowOf[cand] != ce.row)
					rowOf[cand] = -1;
				else {
					rowOf[cand] = ce.row;
					++nRFound[cand];
				}
			}
		}

		foreach (int value; rowOf.keys) {
			if (rowOf[value] != -1 && nRFound[value] > 1) {
				int removed;
				foreach (inout Cell cell; rows[rowOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Row %s must contain %d in box at %s; ",
						            ROWCHAR[rowOf[value]], value, boxes[b][0].toString);
						dout.writefln("eliminated %d candidates for %d.", removed, value);
					}
					changed = true;
				}
			}
		}

		if (changed)
			return changed;
	}

	return changed;
}

// if n cells in the same row/column/block have altogether only n different candidates,
// can remove those candidates from the others in that row/column/block
bool nakedSubset() {
	const char[] name = "Naked subsets";
	bool changed;

	void generalFunction(Cell[] area, char[] str) {
		foreach (int i, Cell cell; area) {
			int[] cands = cell.candidates;
			int candNumber = cands.length;

			void recurse(Cell[] cells) {
				if (cells.length < candNumber) {
					for (int j = 0; j < area.length; ++j) {
						Cell c = area[j];
						bool sameCands;

						if (cells.contains(c))
							continue;

						if (c.candidates.length > 0) {
							sameCands = true;
							foreach (int candidate; c.candidates) {
								if (!cands.contains(candidate)) {
									sameCands = false;
									break;
								}
							}
						}

						if (sameCands) {
							recurse(cells ~ c);
							break;
						}
					}

				} else {
					if (cells.length == candNumber) {
						int removed;

						foreach (Cell c; area) {
							foreach (Cell found; cells)
								if (c is found)
									goto cont;

							removed += c.removeCandidates(cands);

							cont:;
						}

						if (removed > 0) {
							if (explain) {
								char[] cellList, candList;
								foreach (Cell c; cells.sort)
									cellList ~= format("%s, ", c.toString);
								foreach (int i; cands)
									candList ~= format("%d, ", i);

								dout.writef("Cells %s must contain %s; ",
								            // shave off the extra ", "s
								            cellList[0..$-2],
								            candList[0..$-2]
								);

								dout.writefln("eliminated %d such candidates in %s.", removed, str);
							}
							changed = true;

							if (someStats) switch (candNumber) {
								case 2:	++statistics["Naked pairs"];       break;
								case 3: ++statistics["Naked triplets"];    break;
								case 4: ++statistics["Naked quadruplets"]; break;
								// screw quintuplets etc.
								default: ++statistics[format("%s (n=%d)", name, candNumber)];
							}
						}
					}
				}
			}

			// http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
			// as to why dim/2
			if (candNumber > 1 && candNumber <= dim/2) {
				Cell[] cells;
				cells ~= cell;
				recurse(cells);
			}
		}
	}

	foreach (int i, inout Cell[] row; rows) {
		generalFunction(row, format("row ", ROWCHAR[i]));
		if (changed) return changed;
	}
	foreach (int i, inout Cell[] col; cols) {
		generalFunction(col, format("column ", i + 1));
		if (changed) return changed;
	}
	foreach (inout Cell[] box; boxes) {
		generalFunction(box, format("box at %s", box[0].toString));
		if (changed) return changed;
	}


	return changed;
}

bool hiddenSubset() {
	const char[] name = "Hidden subsets";
	bool changed;

	void generalFunction(Cell[] area) {
		// http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
		// as to why (dim-1)/2
		for (int n = 2; n <= (dim-1)/2; ++n) {
			Cell[][] found;
			found.length = dim;

			for (int val = 1; val <= dim; ++val) {
				foreach (Cell c; area)
					if (c.candidates.contains(val))
						found[val-1] ~= c;

				if (found[val-1].length != n)
					found[val-1].length = 0;
			}

			// now e.g. found[0] is all the Cells with candidate 1

			auto p = new Parter!(Cell[])(found, n);
			Cell[][] subFound;

			while ((subFound = p.next()) !is null) {

				// make sure they're all the same
				// and figure out which numbers we're looking at
				Cell[] firstList;
				int[] vals;
				foreach (int i, Cell[] inSub; subFound) {
					if (i == 0)
						firstList = inSub;
					else if (inSub != firstList)
						goto continueOuter;

					foreach (int i, Cell[] cs; found)
						if (inSub == cs && !vals.contains(i+1))
							vals ~= i+1;
				}

				// OK, they're the same

				// remove all other candidates from each Cell
				// can loop through only first one in subFound since they're all the same

				int removed;
				char[] cellList;
				foreach (inout Cell c; subFound[0]) {
					removed += c.removeCandidatesExcept(vals);
					cellList ~= format("%s, ", c.toString);
				}

				if (removed > 0) {
					if (explain) {
						char[] candList;
						foreach (int i; vals)
							candList ~= format("%d, ", i);

						dout.writef("Cells %s must contain %s; ",
						            // shave off the extra ", "s
						            cellList[0..$-2],
						            candList[0..$-2]
						);

						dout.writefln("eliminated %d other candidates from them.", removed);
					}
					changed = true;

					if (someStats) switch (n) {
						case 2:	++statistics["Hidden pairs"];       break;
						case 3: ++statistics["Hidden triplets"];    break;
						case 4: ++statistics["Hidden quadruplets"]; break;
						default: ++statistics[format("%s (n=%d)", name, n)];
					}
				}

				continueOuter:;
			}
		}
	}

	foreach (inout Cell[] row; rows) {
		generalFunction(row);
		if (changed) return changed;
	}
	foreach (inout Cell[] col; cols) {
		generalFunction(col);
		if (changed) return changed;
	}
	foreach (inout Cell[] box; boxes) {
		generalFunction(box);
		if (changed) return changed;
	}

	return changed;
}

// most understandable general definition I found:
// http://www.setbb.com/phpbb/viewtopic.php?t=240&mforum=sudoku
/+
Look for N columns (2 for X-wing, 3 for the Swordfish, 4 for a Jellyfish, 5 for a Squirmbag) with 2 to N candidate cells for ONE given digit. If these fall on exactly N common rows, then all N rows can be cleared of that digit (except in the defining cells!). The test can also be done swapping rows for columns.
+/
// cheers to MadOverlord there for getting the idea of a 9x9 fish being called a Cthulhu
bool ichthyology() {
	const char[] name = "Ichthyology";
	bool changed;

	// a fish can be at most of size dim/2
	// since fish of n=a in rows is a fish of n=dim-a in cols
	for (int n = 2; n <= dim/2; ++n) {
		// rows first
		for (int val = 1; val <= dim; ++val) {
			Cell[][] found;

			foreach (int i, Cell[] row; rows) {
				Cell[] cs;

				// put the candidate cells from row to cs
				foreach (Cell c; row)
					if (c.candidates.contains(val))
						cs ~= c;

				if (cs.length >= 2 && cs.length <= n)
					found ~= cs.dup;
			}

			// so now found contains all the rows with 2 to n candidates for val
			// so we need to look at every subset of size n of found
			// that is, every n rows of found
			auto p = new Parter!(Cell[])(found, n);
			Cell[][] subFound;

			while ((subFound = p.next()) !is null) {
				// count the number of different columns in subFound
				// and make sure they add up to n
				int number, firstNumber;
				bool[int] seenCols, foundRows;
				char[] cellList;
				foreach (int i, Cell[] row; subFound) {
					foreach (Cell c; row) {
						cellList ~= format("%s, ", c.toString);

						if (!(c.col in seenCols)) {
							seenCols[c.col] = true;
							++number;
						}
					}

					foundRows[row[0].row] = true;
				}

				if (number != n)
					continue;

				// if got this far, can remove the candidates for val from all seen cols
				// except from those cells whose row was found - they're the intersection points
				int removed;
				char[] rowList;
				bool[int] listedRows;

				foreach (int i; seenCols.keys) {
					foreach (inout Cell c; cols[i]) {
						if (c.row in foundRows) {
							if (!(c.row in listedRows)) {
								rowList ~= format("%s, ", ROWCHAR[c.row]);
								listedRows[c.row] = true;
							}
						} else
							removed += c.removeCandidates(val);
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
							val
						);

						dout.writefln(
							"eliminated %d candidates for %d in rows %s.",
							removed, val, rowList[0..$-2]
						);
					}

					changed = true;

					if (someStats) {
						if (n == 2 || n == 5 || n == 9)
							++statistics[specificName ~ 's'];
						else if (n == 3 || n == 4)
							++statistics[specificName];
						else
							++statistics[format("%s (n=%d)", name, n)];
					}
				}
			}
		}

		if (changed)
			return changed;

		// columns now...
		for (int val = 1; val <= dim; ++val) {
			Cell[][] found;

			foreach (int i, Cell[] col; cols) {
				Cell[] cs;

				// get the candidate cells in cs
				foreach (Cell c; col)
					if (c.candidates.contains(val))
						cs ~= c;

				if (cs.length >= 2 && cs.length <= n)
					found ~= cs.dup;
			}

			auto p = new Parter!(Cell[])(found, n);
			Cell[][] subFound;
			while ((subFound = p.next()) !is null) {

				int number, firstNumber;
				bool[int] seenRows, foundCols;
				char[] cellList;
				foreach (int i, Cell[] col; subFound) {
					foreach (Cell c; col) {
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
				char[] colList;
				bool[int] listedCols;
				foreach (int i; seenRows.keys) {
					foreach (inout Cell c; rows[i]) {
						if (c.col in foundCols) {
							if (!(c.col in listedCols)) {
								colList  ~= format("%d, ", c.col+1);
								listedCols[c.col] = true;
							}
						} else
							removed += c.removeCandidates(val);
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
							val
						);

						dout.writefln(
							"eliminated %d candidates for %d in columns %s.",
							removed, val, colList[0..$-2]
						);
					}

					changed = true;

					if (someStats) {
						if (n == 2 || n == 5 || n == 9)
							++statistics[specificName ~ 's'];
						else if (n == 3 || n == 4)
							++statistics[specificName];
						else
							++statistics[format("%s (n=%d)", name, n)];
					}
				}
			}
		}

		if (changed)
			return changed;
	}

	return changed;
}

// utility
//////////

void updateCandidates() {
	foreach (inout Cell cell; grid)
		updateCandidates(cell);
}

void updateCandidates(Cell cell) {
	int[] impossible;

	foreach (Cell c; rows [cell.row])
		impossible ~= c.val;
	foreach (Cell c; cols [cell.col])
		impossible ~= c.val;
	foreach (Cell c; boxes[cell.box])
		impossible ~= c.val;
	cell.removeCandidates(impossible);
}

void updateCandidatesAffectedBy(Cell cell) {
	foreach (inout Cell c; rows[cell.row])
		if (cell !is c)
			updateCandidates(c);

	foreach (inout Cell c; cols[cell.col])
		if (cell !is c)
			updateCandidates(c);

	foreach (inout Cell c; boxes[cell.box])
		if (cell !is c)
			updateCandidates(c);
}

bool valid() {
	// no values available for a location
	foreach (Cell cell; grid)
		if (cell.candidates.length == 0 && cell.val == NONE)
			return false;

	bool areaCheck(Cell[] area) {
		bit[int] found, foundCandidate;

		foreach (Cell cell; area) {
			// some value twice in this area
			if (cell.val != NONE && cell.val in found)
				return false;

			foreach (int i; cell.candidates)
				foundCandidate[i] = true;

			found[cell.val] = true;
		}

		// no candidates or values for a value in this area
		for (int i = 1; i <= dim; ++i)
			if (!(i in found || i in foundCandidate))
				return false;

		return true;
	}

	foreach (Cell[] row; rows)
		if (!areaCheck(row))
			return false;
	foreach (Cell[] col; cols)
		if (!areaCheck(col))
			return false;
	foreach (Cell[] box; boxes)
		if (!areaCheck(box))
			return false;

	return true;
}

// note that this does not test for validity
bool solved() {
	foreach (Cell cell; grid)
		if (cell.val == NONE)
			return false;

	return true;
}

// Dancing Links - thanks to Donald E. Knuth
////////////////

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

// output
//////////

// how many characters we want to pad/spread our numbers and chars to
int charWidth;

char[] spread(char c, int n = charWidth) {
	char[] tmp;
	for (int i = 0; i < n; ++i)
		tmp ~= c;
	return tmp;
}

void printGrid() {
	// space out a bit
	if (explain || stats)
		dout.writefln();

	if (ssckCompatible) {
		foreach (int i, Cell c; grid) {
			if (i > 0 && i % dim == 0)
				dout.writef('+');

			if (c.val == EMPTY)
				dout.writef(spread('_'));
			else
				dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, c.val);
		}
	} else if (terseOutput) {
		if (charWidth > 1)
			dout.writef("!%d!", charWidth);
		foreach (int i, Cell c; grid) {
			/+if (dim != 9 && i > 0 && i % dim == 0)
				dout.writef('+');+/

			if (c.val == EMPTY)
				dout.writef(spread('.'));
			else
				dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, c.val);
		}
	} else {
		void horizRule() {
			char[] tmp;
			for (int i = 0; i < prettyPrintInterval; ++i) {
				for (int j = 0; j < prettyPrintInterval; ++j)
					tmp ~= spread('-', charWidth > 1 ? charWidth + 1 : charWidth);
				tmp ~= '+';
			}

			// lose the last +
			dout.writefln(showKey ? " +" : "", tmp[0 .. $-1]);
		}

		if (done)
			dout.writefln("Solved!\n");

		if (showKey) {
			// the column values

			// skip past the row values and the left border
			dout.writef("  ");

			for (int i = 0, j = 0; j < dim; ++i) {
				if (i > 0 && i % prettyPrintInterval == 0)
					// skip the vertical border
					dout.writef(' ');

				dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, ++j);
			}
			dout.writefln();
			horizRule();
		}

		foreach (int i, Cell[] row; rows) {
			if (i > 0 && i % prettyPrintInterval == 0)
				horizRule();

			if (showKey)
				dout.writef("%s|", ROWCHAR[i]);

			foreach (int j, Cell c; row) {
				if (j > 0 && j % prettyPrintInterval == 0)
					dout.writef('|');

				if (c.val == EMPTY)
					dout.writef(charWidth > 1 ? " " : "", spread('.', charWidth));
				else
					dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, c.val);

			}
			dout.writefln();
		}
	}

	dout.writefln();
}

void printCandidates() {
	dout.writefln();
	foreach (Cell[] row; rows) {
		foreach (Cell c; row) {
			dout.writef("|");
			int found;
			for (int i = 0; i <= dim; ++i) {
				if (c.candidates.contains(i)) {
					dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, i);
					++found;
				}
			}
			// -9 since the first 9 have only 1 char
			// this is a very crap formula which gives incorrect results sometimes when dim is > 9.
			// can't be bothered to fix it.
			dout.writef(spread(' ', (charWidth+1)*dim - found - 9));
		}
		dout.writefln("|");
	}
	dout.writefln();
}
