// globals, stuff needed everywhere, etc.

module sudoku.defs;

private import
	std.cstream,
	std.math,
	std.string;

const char[] EMPTIES  = "._0";
const char[] NEWLINES = "+\n";


package:


const int NONE = -1;
alias NONE EMPTY;

Cell[] grid;
Cell[][] rows, cols, boxes;

// behaviour
bit checkValidity,
    someStats,
    noSolve;
int dim = 9;

ulong[char[]] totalStatistics;
ulong         totalIterations;
long          totalTime;
ulong         completed, number;

class Cell {
	int val;
	int row, col, box;
	int[] candidates;

	int removeCandidates(int[] impossible...) {
		int removed;
		bool[int] checked;

		foreach (int i; impossible) {
			if (i in checked || i == NONE)
				continue;
			else
				checked[i] = true;

			int pos = find(i);

			if (pos != -1) {
				++removed;
				candidates = candidates[0..pos] ~ candidates[pos+1..$];
			}
		}

		return removed;
	}

	int removeCandidatesExcept(int[] only...) {
		int removed;

		for (int i = 1; i <= dim; ++i) {
			if (only.contains(i))
				continue;

			int pos = find(i);

			if (pos != -1) {
				++removed;
				candidates = candidates[0..pos] ~ candidates[pos+1..$];
			}
		}

		return removed;
	}



	int opCmp(Object o) {
		Cell c = cast(Cell)o;

		return (dim+1)*(this.row - c.row) + (this.col - c.col);
	}

	char[] toString() {
		return format("[%s%d]", ROWCHAR[row], col + 1);
	}

	private ptrdiff_t find(int i) {
		ptrdiff_t p = -1;
		foreach (ptrdiff_t j, int n; candidates) {
			if (i == n) {
				p = j;
				break;
			}
		}
		return p;
	}
}

int contains(char[] a, char c) {
	foreach (char ch; a)
		if (ch == c)
			return true;
	return false;
}
int contains(int[] a, int n) {
	foreach (int i; a)
		if (i == n)
			return true;
	return false;
}
int contains(Cell[] a, Cell c) {
	foreach (Cell ce; a)
		if (ce is c)
			return true;
	return false;
}

class Parter(T) {
	this(T[] a, size_t n) {
		arr = a.dup;
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
		T[][] a;
		T[] tmp;
		while ((tmp = this.next()) !is null)
			a ~= tmp;
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

const char[] ROWCHAR;
static this() {
	for (int i = 0; i < 26; ++i)
		ROWCHAR ~= i + 'A';
	for (int i = 0; i < 26; ++i)
		ROWCHAR ~= i + 'a';
	ROWCHAR ~= "\\?+/`'*^!@#$%&{}()=<>|,.-;:_ ";

	LN9 = log(9);
}
