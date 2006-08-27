// globals, stuff needed everywhere, etc.

module deesudoku.defs;

import std.bitarray;
import std.cstream;
import std.math;
import std.string;

const char[] EMPTIES  = "._0,xX";

// output formatting...
bool numberedRows = true,
     numberedCols = true,
     bracketCells = false,
     rowFirst     = true;

const int NONE = 0;
alias NONE EMPTY;

Cell[] grid;
Cell[][] rows, cols, boxes;

// behaviour
bool checkValidity,
     someStats,
     noSolve,
     rowNums,
     guessing;
int dim = 9;

ulong[char[]] totalStatistics;
ulong         totalIterations, totalGuessIterations,
              totalGuesses, totalCorGuesses;
long          totalTime;
ulong         completed, number;

uint function(BitArray) bitCount;

// with many thanks to http://www.setbb.com/phpbb/viewtopic.php?t=231&start=15&mforum=sudoku
uint bitCountFast(TYPE)(BitArray ba) {
	TYPE n = *cast(TYPE*)cast(void[])ba;

	uint c = 0;
	for (; n; n &= n-1)
		++c;
	return c;
}
uint bitCountSlow(BitArray ba) {
	uint c = 0;
	foreach (b; ba)
		if (b)
			++c;
	return c;
}

void initDefs() {
	if      (dim <= 32) bitCount = &bitCountFast!(uint);
	else if (dim <= 64) bitCount = &bitCountFast!(ulong);
	else                bitCount = &bitCountSlow;
}

class Cell {
	int val = NONE;
	int row, col, box;
	BitArray candidates;
	int candNum;

	// note that n is an array index; the actual candidate is n+1
	int removeCandidate(int n) {
		if (!candNum)
			return 0;

		if (candidates[n]) {
			candidates[n] = false;
			--candNum;
			return 1;
		}

		return 0;
	}

	int removeCandidates(BitArray impossible) {
		if (!candNum)
			return 0;

		assert (candidates.length == impossible.length);

		int removed = 0;
		for (int i = 0; i < candidates.length; ++i) {
			if (impossible[i] && candidates[i]) {
				candidates[i] = false;
				++removed;
				--candNum;
			}
		}

		return removed;
	}

	int removeCandidatesExcept(BitArray only)
	in {
		assert (only.length == candidates.length);
	} body {
		if (!candNum)
			return 0;

		int removed = 0;
		for (int i = 0; i < candidates.length; ++i) {
			if (!only[i] && candidates[i]) {
				candidates[i] = false;
				++removed;
				--candNum;
			}
		}

		return removed;
	}

	Cell[] buddies() {
		Cell[] bs = new Cell[3*(dim-1)];
		int i;

		foreach (Cell c; rows [row])
			if (this !is c)
				bs[i++] = c;
		foreach (Cell c; cols [col])
			if (this !is c)
				bs[i++] = c;
		foreach (Cell c; boxes[box])
			if (this !is c)
				bs[i++] = c;
		bs.length = i;

		return bs;
	}

	// for sorting
	int opCmp(Object o) {
		Cell c = cast(Cell)o;

		return (dim+1)*(this.row - c.row) + (this.col - c.col);
	}

	char[] toString() {
		if (rowNums)
			return format("r%dc%d", row + 1, col + 1);
		else
			return format("[%s%d]", ROWCHAR[row], col + 1);
	}
}

bool contains(BitArray a, BitArray b)
in {
	assert (a.length == dim);
	assert (b.length == dim);
} body {
	for (int i = 0; i < dim; ++i)
		if (b[i] && !a[i])
			return false;
	return true;
}
bool contains(int[] a, int n) {
	foreach (int i; a)
		if (i == n)
			return true;
	return false;
}
bool contains(char[] a, char c) {
	foreach (char ch; a)
		if (ch == c)
			return true;
	return false;
}
bool contains(Cell[] a, Cell c) {
	foreach (Cell ce; a)
		if (ce is c)
			return true;
	return false;
}

class Parter(T) {
	this(T[] a, size_t n) {
		arr = a;
		positions.length = n;

		// initialize positions so that positions[$-1] = 0, positions[0]=n-1
		foreach (size_t i, inout size_t pos; positions)
			pos = n - (i + 1);

		// so that tryInc() behaves correctly the first time it is called
		--positions[0];
	}

	T[] next() {
		if (!tryInc(0))
			return null;

		T[] sub;
		sub.length = positions.length;
		foreach (size_t i, size_t pos; positions)
			// right order
			sub[$ - (i+1)] = arr[pos];

		return sub;
	}

	T[][] all()
	out {
		assert (this.next() is null);
	} body {
		// here the most common biggest is the binomial coefficient 9 choose 4
		// since usually we'll be having a dim of 9 and searching for up to dim/2
		// so we initialise to that value, as it covers most cases
		T[][] a = new T[][126];
		T[] tmp;
		int i;
		while ((tmp = this.next()) !is null) {
			if (i >= a.length)
				a.length = 2*a.length;
			a[i++] = tmp;
		}
		a.length = i;
		return a;
	}

	private:
		bool tryInc(size_t pos) {
			if (pos >= positions.length)
				return false;

			if (++positions[pos] >= arr.length - pos) {
				if (!tryInc(pos+1))
					return false;

				positions[pos] = positions[pos+1] + 1;
				if (positions[pos] >= arr.length)
					return false;
			}

			return true;
		}

		T[] arr;
		size_t[] positions;

	unittest {
		const int[] a = [1, 2, 3, 4, 5, 6];
		auto p = new Parter!(int)(a, 2);
		int[][] all = p.all();
		assert (p.next is null);

		assert (all.length == 15);
		assert (all[ 0][0] == 1 && all[ 0][1] == 2);
		assert (all[ 1][0] == 1 && all[ 1][1] == 3);
		assert (all[ 2][0] == 1 && all[ 2][1] == 4);
		assert (all[ 3][0] == 1 && all[ 3][1] == 5);
		assert (all[ 4][0] == 1 && all[ 4][1] == 6);
		assert (all[ 5][0] == 2 && all[ 5][1] == 3);
		assert (all[ 6][0] == 2 && all[ 6][1] == 4);
		assert (all[ 7][0] == 2 && all[ 7][1] == 5);
		assert (all[ 8][0] == 2 && all[ 8][1] == 6);
		assert (all[ 9][0] == 3 && all[ 9][1] == 4);
		assert (all[10][0] == 3 && all[10][1] == 5);
		assert (all[11][0] == 3 && all[11][1] == 6);
		assert (all[12][0] == 4 && all[12][1] == 5);
		assert (all[13][0] == 4 && all[13][1] == 6);
		assert (all[14][0] == 5 && all[14][1] == 6);

		p = new Parter!(int)(a, 6);
		int[] six = p.next();
		assert (p.next is null);

		assert (six == a);

		const int[] b = [1, 2, 3, 4];
		p = new Parter!(int)(b, 3);
		int[][] uneven = p.all();

		assert (p.next is null);

		assert (uneven.length == 4);
		assert (uneven[ 0][0] == 1 && uneven[ 0][1] == 2 && uneven[ 0][2] == 3);
		assert (uneven[ 1][0] == 1 && uneven[ 1][1] == 2 && uneven[ 1][2] == 4);
		assert (uneven[ 2][0] == 1 && uneven[ 2][1] == 3 && uneven[ 2][2] == 4);
		assert (uneven[ 3][0] == 2 && uneven[ 3][1] == 3 && uneven[ 3][2] == 4);

		p = new Parter!(int)(a, 1);
		foreach (size_t i, int[] ar; p.all()) {
			assert (ar.length ==    1);
			assert (ar[0]     == a[i]);
		}
	}
}

const real LN9;
real log9(real x) { return log(x) / LN9; }

char[] getRow(int i) {
	if (rowNums)
		return toString(i + 1);
	else
		return toString(ROWCHAR[i]);
}

const char[] ROWCHAR;
static this() {
	for (int i = 0; i < 26; ++i)
		ROWCHAR ~= i + 'A';
	for (int i = 0; i < 26; ++i)
		ROWCHAR ~= i + 'a';

	LN9 = log(9);
}
