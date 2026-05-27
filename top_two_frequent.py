from collections import Counter

def top_two_frequent(nums):
    """Return the top 2 most frequent numbers from a list of integers.
    If there's a tie in frequency, the smaller number comes first.
    """
    # Count frequencies, then sort by (-frequency, value) so that:
    #   - higher frequency comes first
    #   - smaller number breaks ties
    counts = Counter(nums)
    sorted_items = sorted(counts.items(), key=lambda x: (-x[1], x[0]))
    return [num for num, _ in sorted_items[:2]]


# Example usage
example = [1, 2, 3, 2, 4, 1, 2, 3, 3, 3]
result = top_two_frequent(example)
print(f"Input:  {example}")
print(f"Top 2 most frequent: {result}")

# Tie-breaking example
example2 = [5, 5, 7, 7, 9]
result2 = top_two_frequent(example2)
print(f"\nInput:  {example2}")
print(f"Top 2 most frequent: {result2}")
