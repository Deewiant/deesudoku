module sudoku.sudoku;

private import
	std.conv,
	std.cstream,
	std.math,
	std.string,
	std.c.stdlib, // good old exit()
	sudoku.defs,
	sudoku.solver;

const char[] VERSION = "DeewiantSudoku 1.0.0 © Matti \"Deewiant\" Niemenmaa 2006.",
             HELPMSG =
"Usage: sudoku [OPTION]...
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
  -ng,   --no-grid           Do not display even the final, solved grid.
  -to,   --terse-output      Use non-human-readable, terse output.
  -ssck, --suso-co-uk        Use output like that at http://sudokusolver.co.uk/.

Behaviour:
  -cv,   --check-validity    Check validity on every iteration; skip if invalid.",
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
0 8 0 0 0 0 0 6 0";

int main(char[][] args) {
	try foreach (char[] arg; args[1..$]) {
		if (arg.length > 2 && arg[0..2] == "-d")
			dim = toInt(arg[2..$]);
		else if (arg.length > 3 && arg[0..3] == "-d=")
			dim = toInt(arg[3..$]);
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

	if (dim > ROWCHAR.length && (showCandidates || showKey || explain)) {
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
		quit(42);
	}

	prettyPrintInterval = sqrtDim;

	while (!din.eof) {
		if (load(sqrtDim)) {
			if (explain) {
				dout.writefln("\n--- Starting a new 数独 puzzle... ---\n");
				dout.flush();
			}
			
			++number;
			solve();
		} else quit(666);
	}

	quit(0);
	
	return 999;
}

void quit(int n) {
	if (totalStats)
		printStats(totalStatistics, totalIterations, true);
	
	std.c.stdlib.exit(n);
}

bool first;

int load(int sqrtDim) {
	// zero the situation so that old data doesn't corrupt the new
	if (!first) {
		grid.length = 0;
		rows.length = cols.length = boxes.length = 0;
		first = false;
	}

	grid.length = dim * dim;
	rows.length = cols.length = boxes.length = dim;

	foreach (inout Cell[] row; rows)
		row.length = dim;
	foreach (inout Cell[] col; cols)
		col.length = dim;
	// boxes purposefully left out

	// the initial array for each cell's candidates
	int[] all;
	all.length = dim;
	foreach (int j, inout int i; all)
		i = j + 1;

	// counters
	// g is for the grid[]
	// lastG is to ignore lines that contain no cells
	int g, lastG, row, col, box;

	bit terseMode;
	int terseWidth;

	// how many chars one cell takes
	int cellWidth = cast(int)ceil(log9(dim));

	try while (row < dim) {
		if (din.eof)
			return false;

		char ch = din.getc();

		// skip row on comment
		if (ch == '#') while ((ch = din.getc()) != '\n') {}

		if (ch == '!') {
			terseMode = true;

			char tmp;
			char[] str;
			while (std.string.digits.contains(tmp = din.getc()))
				str ~= tmp;
			// no ungetc since we want to lose the last '!'
			terseWidth = toInt(str);

			continue;
		}

		if (col == dim) {
			++row;
			col = 0;
			lastG = g;
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
				while (EMPTIES.contains(tmp = din.getc())){}
				din.ungetc(tmp);
			}

			cell.val = EMPTY;
			cell.candidates = all.dup;

			add(cell);

		} else if (std.string.digits.contains(ch)) {
			char tmp;
			char[] str;
			str ~= ch;
			if (terseMode) {
				int i = terseWidth;
				while (--i) {
					tmp = din.getc();
					str ~= tmp;
				}
			} else if (cellWidth > 1) {
				while (std.string.digits.contains(tmp = din.getc()))
					str ~= tmp;
			}
			din.ungetc(tmp);

			cell.val = toUint(str);

			add(cell);

		} else if (g != lastG && NEWLINES.contains(ch)) {
			++row;
			col = 0;
			lastG = g;
		}
	} catch (Exception e) {
		derr.writefln("Failed to load a Sudoku.\n\nPossible causes:");
		derr.writefln("\t- Excess characters within the Sudoku: make sure comments are on lines\n\t  starting with #!");
		derr.writefln("\t- Wrong character types: all of \"%s\" are considered empty cells, and\n\t  only numbers can be used as cell values.", EMPTIES);
		derr.writefln("\t- Incorrect dimensions given: by default, Sudokus are assumed to be\n\t  9*9. Use the -d argument to specify an alternate dimensionality.");
		derr.writefln("\t- A strangely shaped Sudoku: only square Sudokus are supported.");
		derr.writefln("\nHalting further attempts - any loaded data will likely be corrupted.");
		return false;
	}

	return true;
}
