module sudoku.solver;

private import
	std.cstream,
	std.math,
	std.perf,
	std.string,
	sudoku.defs,
	sudoku.output;

void solve() {
	bool changed;
	ulong iterations;
	long time; // no see

	TickCounter timer = new TickCounter();
	if (someStats) {
		foreach (char[] s; statistics.keys)
			statistics.remove(s);
		timer.start();
	}

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

		if (someStats)
			++iterations;

		foreach (bool function() method; methods)
			if (changed = method(), changed)
				break;

		if (solved()) {
			done = true;
			break;
		}

		if (!noGrid || explain || stats || checkValidity)
			dout.flush();
	} while (changed);

	if (someStats) {
		timer.stop();
		time = timer.milliseconds();
	}

	// if showGrid is on, it was already printed
	if (!showGrid && !noGrid)
		printGrid();

	if (totalStats) {
		foreach (char[] s, ulong n; statistics)
			totalStatistics[s] += n;
		totalIterations += iterations;
		totalTime       += time;

		if (done)
			++completed;
	}

	if (stats)
		printStats(statistics, iterations, time);
}

private:

const bool function()[] methods;
// statistics mostly use the names at http://www.simes.clara.co.uk/programs/sudokutechniques.htm
ulong[char[]] statistics;

static this() {
	// ordered according to their likelihood of being useful
	// this increases speed (reduces iterations) somewhat

	// ichthyology implemented before XY-wing but the latter is more common
	methods ~= &expandSingleCandidates;
	methods ~= &assignUniques;
	methods ~= &checkConstraints;
	methods ~= &nakedSubset;
	methods ~= &hiddenSubset;
	methods ~= &xyzWing;
	methods ~= &xyWing;
	methods ~= &ichthyology;
}

// solving
//////////

// if a cell has only a single candidate, set that cell's value to the candidate
bool expandSingleCandidates() {
	const char[] name = "Naked singles";
	bool changed;

	foreach (Cell c; grid) {
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

	foreach (Cell[] row; rows) {
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

	foreach (Cell[] col; cols) {
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

				changed = true;
			}
		}
	}

	foreach (Cell[] box; boxes) {
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

				changed = true;
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

	bool rowColFunc(int r, Cell[] row, char[] str, bool col) {
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
				foreach (Cell cell; boxes[boxOf[value]])
					if ((col && cell.col != r) || (!col && cell.row != r))
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Box at %s must contain %d in %s; ",
						            boxes[boxOf[value]][0].toString,
						            value,
						            str
						);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value);
					}

					if (someStats)
						++statistics[name];

					return true;
				}
			}
		}

		return false;
	}

	foreach (int r, Cell[] row; rows)
		if (rowColFunc(r, row, format("row %s", getRow(r)), false))
			return true;
	foreach (int c, Cell[] col; cols)
		if (rowColFunc(c, col, format("column %d", c + 1), true))
			return true;

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
				foreach (Cell cell; cols[colOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Column %d must contain %d in box at %s; ",
						            colOf[value] + 1, value, boxes[b][0].toString);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value);
					}

					if (someStats)
						++statistics[name];

					return true;
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
				foreach (Cell cell; rows[rowOf[value]])
					if (cell.box != b)
						removed += cell.removeCandidates(value);

				if (removed > 0) {
					if (explain) {
						dout.writef("Row %s must contain %d in box at %s; ",
						            getRow(rowOf[value]), value, boxes[b][0].toString);
						dout.writefln("eliminated %s for %d.", nCandidates(removed), value);
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
								if (!cands.hasCandidate(candidate)) {
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

								dout.writefln("eliminated %s in %s.", nCandidates(removed, "such"), str);
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

	foreach (int i, Cell[] row; rows) {
		generalFunction(row, format("row ", getRow(i)));
		if (changed) return changed;
	}
	foreach (int i, Cell[] col; cols) {
		generalFunction(col, format("column ", i + 1));
		if (changed) return changed;
	}
	foreach (Cell[] box; boxes) {
		generalFunction(box, format("box at %s", box[0].toString));
		if (changed) return changed;
	}


	return changed;
}

// http://www.simes.clara.co.uk/programs/sudokutechnique9.htm puts it concisely:
// If there are N cells with N candidates between them that don't appear
// elsewhere in the same row, column or block, then any other candidates
// for those cells can be eliminated.
bool hiddenSubset() {
	const char[] name = "Hidden subsets";

	// http://www.setbb.com/phpbb/viewtopic.php?t=273&mforum=sudoku
	// as to why (dim-1)/2
	int limit = (dim-1)/2;

	bool generalFunction(Cell[] area) {

		Cell[][] each = new Cell[][dim];
		int[] i = new int[dim];

		for (int val = 0; val < dim; ++val) {
			each[val].length = dim;
			foreach (Cell c; area)
				if (c.candidates.hasCandidate(val+1))
					each[val][i[val]++] = c;
		}

		for (int n = 2; n <= limit; ++n) {
			Cell[][] found = each.dup;

			int upToNCands;
			for (int val = 0; val < dim; ++val) {
				if (i[val] <= n) {
					found[val].length = i[val];
					++upToNCands;
				} else
					found[val].length = 0;
			}

			// now e.g. found[0] is all the Cells in area with candidate 1
			// unless there were more than n such Cells, in which case
			// they couldn't be part of a subset of size n

			// if there weren't enough Cells with up to n candidates no such
			// hidden subset can exist
			if (upToNCands < n)
				break;

			auto p = new Parter!(Cell[])(found, n);
			Cell[][] subFound;
			while ((subFound = p.next()) !is null) {
				// so what we have in subFound are n Cell[]s
				// each of which are all the Cells in area for a certain candidate

				// make sure that there are only n different Cells altogether
				// and figure out which candidates we're looking at

				Cell[] cells = new Cell[n];
				bit[Cell] checked;
				int[] vals = new int[n];
				int j, h;
				foreach (Cell[] inSub; subFound) {
					if (!inSub.length)
						goto continueOuter;

					foreach (Cell c; inSub) {
						if (!(c in checked)) {
							if (h >= n) // oops, too many different cells
								goto continueOuter;

							cells[h++] = c;
							checked[c] = true;
						}
					}

					// figure out the candidates
					for (int k = 1; k <= dim; ++k) {
						if (inSub is found[k-1] && !vals.hasCandidate(k)) {
							if (j >= n) // oops, too many different candidates
								goto continueOuter;

							vals[j++] = k;
						}
					}
				}
				// both for binary search (in Cell.removeCandidatesExcept())
				// to work and to get nicer output when explaining
				vals.sort;

				// OK, we have a hidden subset
				// remove all other candidates from each Cell in cells

				int removed;
				char[] cellList;
				foreach (Cell c; cells) {
					removed += c.removeCandidatesExcept(vals);
					if (explain)
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

					if (someStats) switch (n) {
						case 2:	++statistics["Hidden pairs"];       break;
						case 3: ++statistics["Hidden triplets"];    break;
						case 4: ++statistics["Hidden quadruplets"]; break;
						default: ++statistics[format("%s (n=%d)", name, n)];
					}

					return true;
				}

				continueOuter:;
			}
		}

		return false;
	}

	foreach (Cell[] row; rows)
		if (generalFunction(row))
			return true;
	foreach (Cell[] col; cols)
		if (generalFunction(col))
			return true;
	foreach (Cell[] box; boxes)
		if (generalFunction(box))
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

	// a fish can be at most of size dim/2
	// since fish of n=a in rows is a fish of n=dim-a in cols
	for (int n = 2; n <= dim/2; ++n) {
		// rows first
		for (int val = 1; val <= dim; ++val) {
			Cell[][] found = new Cell[][dim];
			int f = 0;

			foreach (int i, Cell[] row; rows) {
				Cell[] cs = new Cell[dim];
				int s;

				// put the candidate cells from row to cs
				foreach (Cell c; row)
					if (c.candidates.hasCandidate(val))
						cs[s++] = c;

				if (s >= 2 && s <= n) {
					cs.length = s;
					found[f++] = cs.dup;
				}
			}
			found.length = f;

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
						if (explain)
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
					foreach (Cell c; cols[i]) {
						if (c.row in foundRows) {
							if (!(c.row in listedRows)) {
								if (explain)
									rowList ~= format("%s, ", getRow(c.row));
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
							"eliminated %s for %d in rows %s.",
							nCandidates(removed), val, rowList[0..$-2]
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

		// columns now...
		for (int val = 1; val <= dim; ++val) {
			Cell[][] found;

			foreach (int i, Cell[] col; cols) {
				Cell[] cs;

				// get the candidate cells in cs
				foreach (Cell c; col)
					if (c.candidates.hasCandidate(val))
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
				char[] colList;
				bool[int] listedCols;
				foreach (int i; seenRows.keys) {
					foreach (Cell c; rows[i]) {
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
							"eliminated %s for %d in columns %s.",
							nCandidates(removed), val, colList[0..$-2]
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
	}

	return false;
}

// Find a cell with two candidates, X and Y.
// Find two buddies of that cell with candidates X and Z, Y and Z.
// Then can remove Z from the candidates of all cells that are buddies with both of the two buddies.
bool xyWing() {
	const char[] name = "XY-wing";

	foreach (Cell c; grid) {
		if (c.candidates.length != 2)
			continue;

		int X = c.candidates[0],
		    Y = c.candidates[1];

		int[] Z;
		Cell[][] goodGroups;
		goodGroups.length = dim;

		Cell[] cBuddies = c.buddies;

		// find all buddies of c with candidates X and Z.
		// add each one to its own Cell[] in goodGroups.
		// then loop through each Z
		// and find all buddies of c with candidates Y and that Z, and each to the corresponding goodGroup.
		int i;
		foreach (Cell friend; cBuddies) {
			if (friend.candidates.length != 2)
				continue;

			// one of the candidates is also in c (i.e. is X or Y), other is not
			// being sneaky here... if the Z is negative, the other candidate was Y, else it was X
			if (friend.candidates[0] == X && friend.candidates[1] != Y) {
				Z ~= friend.candidates[1];
				goodGroups[i++] ~= friend;
			} else if (friend.candidates[0] == Y && friend.candidates[1] != X) {
				Z ~= -friend.candidates[1];
				goodGroups[i++] ~= friend;
			} else if (friend.candidates[1] == X && friend.candidates[0] != Y) {
				Z ~= friend.candidates[0];
				goodGroups[i++] ~= friend;
			} else if (friend.candidates[1] == Y && friend.candidates[0] != X) {
				Z ~= -friend.candidates[0];
				goodGroups[i++] ~= friend;
			}
		}
		goodGroups.length = i;
		foreach (int i, int z; Z) {
			bool otherIsX = true;
			if (z < 0) {
				z = -z;
				otherIsX = false;
			}
			foreach (Cell friend; cBuddies) {
				if (friend.candidates.length != 2 || !friend.candidates.hasCandidate(z))
					continue;

				if (otherIsX && friend.candidates.hasCandidate(Y))
					goodGroups[i] ~= friend;
				else if (!otherIsX && friend.candidates.hasCandidate(X))
					goodGroups[i] ~= friend;
			}
		}

		foreach (int i, Cell[] goodGroup; goodGroups) {
			if (!goodGroup.length)
				continue;

			auto p = new Parter!(Cell)(goodGroup, 2);
			Cell[] goodPair;
			while ((goodPair = p.next()) !is null) {
				if (goodPair[0].candidates == goodPair[1].candidates)
					continue;

				int removed;

				foreach (Cell target; goodPair[0].buddies)
					if (target !is c && target !is goodPair[1] && areBuddies(target, goodPair[1]))
						removed += target.removeCandidates(Z[i]);

				if (removed > 0) {
					if (explain) {
						dout.writef(
							"Found an %s among %s for %d; ",
							name,
							format("%s, %s, %s", c, goodPair[0], goodPair[1]),
							Z[i]
						);

						dout.writefln(
							"eliminated %s for %d.",
							nCandidates(removed), Z[i]
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

	foreach (Cell XYZ; grid) {
		if (XYZ.candidates.length != 3)
			continue;

		Cell[] XZs;
		int[2][] shared; // i.e. the X and Z candidates
		XZs.length = shared.length = dim - 1;
		int i;
		foreach (Cell XZ; boxes[XYZ.box]) {
			if (XZ.candidates.length != 2 || !XYZ.candidates.hasCandidates(XZ.candidates))
				continue;

			if (XZ.candidates[0] == XYZ.candidates[0]) {
				XZs[i] = XZ;
				shared[i][0] = XYZ.candidates[0];
				if (XZ.candidates[1] == XYZ.candidates[1])
					shared[i++][1] = XYZ.candidates[1];
				else // (XZ.candidates[1] == XYZ.candidates[2])
					shared[i++][1] = XYZ.candidates[2];
			} else if (XZ.candidates[0] == XYZ.candidates[1]) {
				// (XZ.candidates[1] == XYZ.candidates[2])
				XZs[i] = XZ;
				shared[i][0] = XYZ.candidates[1];
				shared[i++][1] = XYZ.candidates[2];
			}
			// there are no other cases since both candidates are sorted
			// and XZ.candidates must be in XYZ.candidates
		}
		XZs.length = shared.length = i;

		// now we have the XZs as well as the Xs and Zs
		// so we need the YZs

		Cell[] YZs = rows[XYZ.row] ~ cols[XYZ.col];
		foreach (Cell YZ; YZs) {
			if (YZ.candidates.length != 2 || !XYZ.candidates.hasCandidates(YZ.candidates) || YZ.box == XYZ.box)
				continue;

			foreach (int i, Cell XZ; XZs) {
				if (YZ.candidates == XZ.candidates)
					continue;

				// so it's an YZ
				// but what's the Z?
				// it must be in shared[i] as well as in YZ
				// and there can be only one such one, or the above if would've been true

				int Z = shared[i][0];
				if (YZ.candidates.hasCandidate(shared[i][1]))
					Z = shared[i][1];

				// yay, proceed with removal
				int removed;
				Cell[] loopThru = YZ.row == XYZ.row ? rows[XYZ.row] : cols[XYZ.col];

				foreach (Cell c; loopThru)
					if (c.box == XYZ.box && c !is XYZ && c !is XZ)
						removed += c.removeCandidates(Z);

				if (removed > 0) {
					if (explain) {
						dout.writef(
							"Found an %s among %s for %d; ",
							name,
							format("%s, %s, %s", XYZ, XZ, YZ),
							Z
						);

						dout.writefln(
							"eliminated %s for %d.",
							nCandidates(removed), Z
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

// utility
//////////

package void updateCandidates() {
	foreach (Cell cell; grid)
		updateCandidates(cell);
}

void updateCandidates(Cell cell) {
	int[] impossible = new int[3*(dim-1)];
	int i;

	foreach (Cell c; rows [cell.row])
		if (!impossible.contains(c.val))
			impossible[i++] = c.val;
	foreach (Cell c; cols [cell.col])
		if (!impossible.contains(c.val))
			impossible[i++] = c.val;
	foreach (Cell c; boxes[cell.box])
		if (!impossible.contains(c.val))
			impossible[i++] = c.val;
	impossible.length = i;

	cell.removeCandidates(impossible);
}

void updateCandidatesAffectedBy(Cell cell) {
	foreach (Cell c; rows [cell.row])
		if (cell !is c)
			updateCandidates(c);
	foreach (Cell c; cols [cell.col])
		if (cell !is c)
			updateCandidates(c);
	foreach (Cell c; boxes[cell.box])
		if (cell !is c)
			updateCandidates(c);
}

bool areBuddies(Cell a, Cell[] b...) {
	foreach (Cell c; b)
		if (a.row != c.row && a.col != c.col && a.box != c.box)
			return false;

	return true;
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
