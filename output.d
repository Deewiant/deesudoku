module deesudoku.output;

import std.cstream : din, dout, derr;
import std.string  : format, toString;
import deesudoku.defs;

debug import std.bitarray;

// verbosity levels
bit showCandidates,
    showGrid,
    showKey,
    explain,
    terseOutput,
    ssckCompatible,
    stats,
    noGrid,
    totalStats;

int prettyPrintInterval;
bool done;

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
	if (number > 1 || explain)
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
			if (c.val == EMPTY)
				dout.writef('.');
			else
				dout.writef("%*d", charWidth, c.val);
		}
		if (explain || someStats)
			dout.writefln();
	} else {
		void horizRule() {
			char[] tmp;
			for (int i = 0; i < prettyPrintInterval; ++i) {
				for (int j = 0; j < prettyPrintInterval; ++j)
					tmp ~= spread('-', charWidth > 1 ? charWidth + 1 : charWidth);
				tmp ~= '+';
			}

			if (showKey)
				dout.writef(spread(' ', rowNums ? charWidth : 1), '+');

			// lose the last +
			dout.writefln(tmp[0 .. $-1]);
		}

		if (showKey) {
			// the column values

			// skip past the row values...
			dout.writef(spread(' ', rowNums ? charWidth : 1));

			// ...and the left border
			dout.writef(' ');

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

			if (showKey) {
				if (rowNums)
					dout.writef("%*d", charWidth, i+1);
				else
					dout.writef("%s", ROWCHAR[i]);

				dout.writef('|');
			}

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

	if (explain)
		dout.writefln();

	dout.flush();
}

void printCandidates() {
	dout.writefln();
	foreach (Cell[] row; rows) {
		foreach (Cell c; row) {
			dout.writef("|");
			int found;
			for (int i = 0; i < dim; ++i) {
				if (c.candNum && c.candidates[i]) {
					dout.writef(charWidth > 1 ? " %*d" : "%*d", charWidth, i+1);
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
	dout.flush();
}

void printStats(ulong[char[]] theStats, ulong iters, long time, ulong guesses, ulong cGuesses, ulong guessIters, bool total = false) {
	// space out
	if (!noGrid || (noGrid && number > 1))
		dout.writefln();

	if (!total && done)
		dout.writefln("Solved!");
	dout.writefln("Solve time: %d ms", time);
	dout.writefln("Iterations: %d%s", iters, guesses > 0 ? " (and "~toString(guessIters)~" in guesses)" : "");

	if (!theStats.length)
		return;

	dout.writefln("Methods used:");
	char[][] strs;
	ulong[] ns;
	strs.length = ns.length = theStats.length;
	int longest;
	int c;
	foreach (char[] s, ulong n; theStats) {
		if (n > 0) {
			strs[c] = s;
			if (s.length > longest)
				longest = s.length;
			ns[c++] = n;
		}
	}

	// selection sort ns to descending order, moving strs as we go
	for (int i = 0; i < ns.length - 1; ++i) {
		int putLeft = i;

		for (int j = i + 1; j < ns.length; ++j)
			if (ns[j] > ns[putLeft])
				putLeft = j;
		char[] tmp;              ulong tmp2;
		tmp = strs[i];           tmp2 = ns[i];
		strs[i] = strs[putLeft]; ns[i] = ns[putLeft];
		strs[putLeft] = tmp;     ns[putLeft] = tmp2;
	}

	foreach (int i, char[] str; strs)
		dout.writefln("\t%s: %*d", str, cast(int)(longest + std.string.toString(ns[i]).length - str.length), ns[i]);

	if (guesses > 0) {
		dout.writefln("\tAnd, unfortunately, %d guess%s, %scorrect.",
			guesses,
			guesses == 1 ? "" : "es",
			cGuesses == 0
				? guesses == 1
					? "which was unluckily in"
					: "none of which were "
				: guesses == cGuesses
					? guesses == 1
						? "which was luckily "
						: "all of which were "
					: format("of which %d %s ", cGuesses, cGuesses == 1 ? "was" : "were")
		);
	}
	
	dout.writefln("%d methods used.", theStats.length);

	if (total)
		dout.writefln("\nSolved %d/%d Sudokus.", completed, number);
	else
		dout.flush(); // no need to flush if total, since it's the last thing anyway
}

char[] nCandidates(int n, char[] str = null) {
	return format("%d %scandidate%s", n, str is null ? "" : str ~ ' ', n == 1 ? "" : "s");
}

debug char[] stringify(BitArray a) {
	char[] s = new char[a.length];
	foreach (size_t i, bit b; a)
		s[i] = format("%d", b)[0];
	return s;
}
