module deesudoku.deesudoku;

import std.bitarray;
import std.conv;
import std.cstream;
import std.math;
import std.string;
import
	deesudoku.defs,
	deesudoku.output,
	deesudoku.solver;

const char[] VERSION = "DeewiantSudoku 3.0.0 alpha 1 © Matti \"Deewiant\" Niemenmaa 2006.",
             HELPMSG =
"Usage: deesudoku [OPTION]...
Attempts to solve all Sudoku puzzles read from standard input.

Only \"purely logical\" methods (and not all of them) are currently supported.
All given puzzles may not be solved.

Input files may contain line comments beginning with a hash, #.
Extraneous characters are skipped as much as possible, but # is safest.

By default, a normal 9*9 Sudoku is assumed.
Use one of -dN, -d=N, --dim=N to specify that the data describes N*N Sudokus.
Only square Sudokus are currently supported.

Startup:
  -v,    --version           Display the version string and exit.
  -h,    --help (and others) Display this help string and exit.
  -ex,   --examples          Show example puzzles in varying formats and exit.

Verbosity:
  -e,    --explain           Explain each step taken toward the solution.
  -ss,   --show-statistics   Display statistics on method use and time taken.
  -ts,   --total-statistics  Display total statistics for all Sudokus attempted.
  -sg,   --show-grid         Show the grid on every iteration.
  -sk,   --show-key          Show the legend around the grid.
  -sc,   --show-candidates   Show the candidate grid on every iteration.
  -rn,   --row-numbers       Use r1c1-style instead of [A1]-style output.
  -ng,   --no-grid           Do not display even the final, solved grid.
  -to,   --terse-output      Use non-human-readable, terse output.
  -ssck, --suso-co-uk        Use output like that at http://sudokusolver.co.uk/.

Behaviour:
  -cv,   --check-validity    Check validity on every iteration; skip if invalid.
  -ns,   --no-solve          Do not solve puzzles; only output initial state.
  -ag,   --allow-guessing    Allow guessing to be utilised when solving.
  -b,    --benchmark         Equivalent to -ts -ag -ng.",
             EXAMPLES =
".....319..1.87...43.7.615..7.9..5..6.........6..1..7.2..854.6.11...38.4..947.....
5_26__7__+___9___1_+______385+__4_961__+_________+__527_9__+837______+_6___9___+__9__82_3
3.7|.4.|...
...|...|.91
8..|...|...
---+---+---
4..|...|7..
...|16.|...
...|25.|...
---+---+---
...|...|38.
.9.|...|5..
.2.|6..|...
7 0 5 0 0 0 0 0 2
0 0 0 4 0 1 0 0 0
3 0 0 0 0 0 0 0 0
0 1 0 6 0 0 4 0 0
2 0 0 0 5 0 0 0 0
0 0 0 0 0 0 0 9 0
0 0 0 3 7 0 0 0 0
0 9 0 0 0 0 8 0 0
0 8 0 0 0 0 0 6 0
69...2..........31...........314....2.....6.....3........71..4.86....5...........
9...6.........184...8.7..5......7..5.7.4..2...1.59.4....1.8....6.......3.4.15...6";

int main(char[][] args) {
	try foreach (char[] arg; args[1..$]) {
		if (arg.length > 3 && arg[0..3] == "-d=")
			dim = toInt(arg[3..$]);
		else if (arg.length > 2 && arg[0..2] == "-d")
			dim = toInt(arg[2..$]);
		else if (arg.length > 6 && arg[0..6] == "--dim=")
			dim = toInt(arg[6..$]);
		else switch (arg) {
			case "--show-candidates", "-sc":
				showCandidates = true;
				break;
			case "--explain", "-e":
				explain = true;
				break;
			case "--show-grid", "-sg":
				showGrid = true;
				break;
			case "--show-key", "-sk":
				showKey = true;
				break;
			case "--terse-output", "-to":
				terseOutput = true;
				break;
			case "--suso-co-uk", "-ssck":
				ssckCompatible = true;
				break;
			case "--show-statistics", "-ss":
				stats = true;
				break;
			case "--no-grid", "-ng":
				noGrid = true;
				break;
			case "--help", "-help", "help", "/?", "-?", "?", "-h", "/h", "h", "-H", "-HELP", "HELP", "--HELP":
				dout.writefln(HELPMSG);
				return 0;
			case "--version", "-v", "-V":
				dout.writefln(VERSION);
				return 0;
			case "--check-validity", "-cv":
				checkValidity = true;
				break;
			case "--examples", "-ex":
				dout.writefln(EXAMPLES);
				return 0;
			case "--total-statistics", "-ts":
				totalStats = true;
				break;
			case "--no-solve", "-ns":
				noSolve = true;
				break;
			case "--row-numbers", "-rn":
				rowNums = true;
				break;
			case "--benchmark", "-b":
				totalStats = true;
				noGrid     = true;
			case "--allow-guessing", "-ag":
				guessing = true;
				break;
			default:
				derr.writefln("Unrecognised argument ", arg);
				break;
		}
	} catch (ConvOverflowError) {
		derr.writefln("Dimension specified is too big. The maximum is %d.", int.max);
		derr.writefln("Assuming 9*9...");
		dim = 9;
	} catch (ConvError e) {
		derr.writefln("Dimension specified is not integral.");
		derr.writefln("Assuming 9*9...");
		dim = 9;
	}

	if (noGrid && (showGrid || showKey || terseOutput || ssckCompatible)) {
		derr.writefln("Having --no-grid take precedence over --show-grid/--show-key/--terse-output/--suso-co-uk...");
		showGrid = showKey = terseOutput = ssckCompatible = false;
	}

	if (noGrid && noSolve && !showCandidates) {
		derr.writefln("--no-solve and --no-grid without --show-candidates leave nothing whatsoever to be done...");
		return 42;
	}

	if (!rowNums && dim > ROWCHAR.length && (showCandidates || showKey || explain)) {
		derr.writefln("Sorry, cannot show candidates or the key or explain with such a large grid -"
		              "there are only %d available characters for rows.", ROWCHAR.length);
		showCandidates = showKey = explain = false;
	}

	if (ssckCompatible) {
		if (dim != 9)
			derr.writefln("Keep in mind that sudokusolver.co.uk doesn't support dimensions other than 9...");

		if (terseOutput) {
			derr.writefln("Terse output doesn't mix with sudokusolver.co.uk.");
			derr.writefln("Using only --suso-co-uk...");
			terseOutput = false;
		}
	}

	if (showKey && terseOutput) {
		derr.writefln("Cannot show the key in terse output.");
		derr.writefln("Ignoring --show-key...");
		showKey = false;
	}

	if (stats || totalStats)
		someStats = true;

	real n = sqrt(cast(float)dim);
	int sqrtDim = cast(int)n;
	if (n != sqrtDim) {
		derr.writefln("Invalid dimension: the dimension must be a square number.");
		return 42;
	}
	prettyPrintInterval = sqrtDim;

	int errorLevel = 0;
	while (!din.eof) {
		if (load(sqrtDim)) {
			charWidth = cast(int)ceil(log9(dim));
			++number;

			if (noSolve) {
				printGrid();

				if (showCandidates) {
					updateCandidates();
					printCandidates();
				}

				continue;
			}

			// no need to init if none was ever loaded
			if (number == 1) {
				initDefs();
				initSolver();
			}

			if (explain) {
				if (number > 1)
					dout.writefln();
				dout.writefln("--- Starting a new 数独 puzzle... ---");
				if (!showGrid)
					dout.writefln();
				dout.flush();
			}

			solve();
		} else {
			errorLevel = 666;
			break;
		}
	}

	if (totalStats)
		printStats(totalStatistics, totalIterations, totalTime, totalGuesses, totalCorGuesses, totalGuessIterations, true);

	return errorLevel;
}

int load(int sqrtDim) {
	// zero the situation so that old data doesn't corrupt the new
	// doesn't need to be done the first time, but whatever
	grid.length = 0;
	rows.length = cols.length = boxes.length = 0;

	grid.length = dim * dim;
	rows.length = cols.length = boxes.length = dim;

	foreach (inout row; rows)
		row.length = dim;
	foreach (inout col; cols)
		col.length = dim;
	// boxes intentionally left out, they're appended to

	// counter for grid[]
	int g = 0;
	bool eof = false;
	try {
		// the initial array for each cell's candidates
		BitArray all;
		all.length = dim;
		for (int i = 0; i < dim; ++i)
			all[i] = 1;

		// more counters
		int row = 0, col = 0, box = 0;

		bool terseMode = false;
		int terseWidth = 0;

		// how many chars one cell takes
		int cellWidth = cast(int)ceil(log9(dim));

		loadLoop: while (g < grid.length) {
			if (din.eof) {
				eof = true;
				break;
			}

			char ch = din.getc;

			static bool lineBreak(inout char ch) {
				if (ch == '\r') {
					ch = din.getc;
					if (ch != '\n')
						din.ungetc(ch);
					return true;
				} else if (ch == '\n')
					return true;
				else
					return false;
			}

			// skip row on comment
			if (ch == '#') while (!lineBreak((ch = din.getc, ch))) {
				if (ch == char.init) {
					eof = true;
					break;
				}
			}

			if (ch == '!') {
				terseMode = true;

				char tmp;
				char[] str;
				while (std.string.digits.contains(tmp = din.getc))
					str ~= tmp;

				if (tmp == char.init) {
					eof = true;
					break;
				}

				// no ungetc since we want to lose the last '!'
				terseWidth = toInt(str);

				continue;
			}

			if (col == dim) {
				// we've added dim Cells, go to next row
				++row;
				col = 0;
			}

			Cell cell = new Cell();
			cell.row = row;
			cell.col = col;
			cell.box = (g % dim) / sqrtDim + row / sqrtDim * sqrtDim;
			// scary integer division tricks
			// alternatively could use an increasing offset:
			// after ++row, put if (row % sqrtDim == 0) offset += sqrtDim;
			// and then box = (g % dim) / sqrtDim + offset

			void add(Cell cell) {
				grid [g++]       = cell;
				rows [row][col]  = cell;
				cols [col][row]  = cell;
				boxes[cell.box] ~= cell;

				++col;
			}

			if (EMPTIES.contains(ch)) {
				if (cellWidth > 1 && !terseMode) {
					char tmp;
					while (EMPTIES.contains(tmp = din.getc)){}
					din.ungetc(tmp);
				}

				cell.val = EMPTY;
				cell.candidates = all.dup;
				cell.candNum = dim;

				add(cell);

			} else if (std.string.digits.contains(ch) || (terseMode && ch == ' ')) {
				char tmp;
				char[] str;
				if (terseMode) {
					if (ch != ' ')
						str ~= ch;

					for (int i = 0; i < terseWidth; ++i) {
						if ((tmp = din.getc) == char.init) {
							eof = true;
							break loadLoop;
						}
						str ~= tmp;
					}
					str = stripr(str);
				} else {
					str ~= ch;
					if (cellWidth > 1)
						while (std.string.digits.contains(tmp = din.getc))
							str ~= tmp;
					din.ungetc(tmp);
				}

				cell.val = toUint(str);
				// just full of zeroes
				cell.candidates.length = dim;
				cell.candNum = 0;

				add(cell);

			}
		}

		if (
			(g > 0 && g != grid.length) || // got some cells, but not enough for a Sudoku
			(terseMode && !terseWidth)     // ran into EOF while reading terseWidth
		) {
			assert (g < grid.length);
			throw new Object;
		}

		if (eof)
			return false;
	} catch {
		derr.writefln("
Failed to load a Sudoku of dimensions %d*%d.

Possible causes:
	- Too little data: expected %d cells, got %d.
	- Excess characters within the Sudoku: make sure comments are on lines
	  starting with a hash (#).
	- Wrong character types: all of \"%s\" are considered empty cells,
	  and only numbers can be used as cell values.
	- Incorrect dimensions given: the default size is 9*9. Use the -d
	  argument to specify an alternate dimensionality.
	- A strangely shaped Sudoku: only square Sudokus are supported.
	- Incorrectly used terse output mode: unpaired exclamation marks (!).

%s",
			dim, dim, grid.length, g, EMPTIES,
			eof ? "Broke at end of file."
			    : "Halting further attempts: any loaded data will likely be corrupted."
		);

		return false;
	}

	return true;
}
