import sys

def get_lines(filename, start, end):
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
            for i in range(start - 1, min(end, len(lines))):
                print(f"{i + 1}: {lines[i]}", end="")
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python get_lines.py <filename> <start_line> <end_line>")
        sys.exit(1)

    filename = sys.argv[1]
    try:
        start_line = int(sys.argv[2])
        end_line = int(sys.argv[3])
    except ValueError:
        print("Error: Start and end lines must be integers.")
        sys.exit(1)

    get_lines(filename, start_line, end_line)
