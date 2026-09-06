import Foundation

/// cl100k_base BPE token counter. Counting only — no decode table is kept.
final class Tokenizer {

    // MARK: - Vocabulary

    /// Byte sequence -> rank. Keyed by a cheap rolling hash of the bytes to avoid
    /// hashing `[UInt8]` on every probe; collisions are resolved by comparing bytes.
    private var ranks: [VocabKey: Int] = [:]

    /// Wraps a byte slice with a precomputed hash so dictionary probes stay cheap.
    private struct VocabKey: Hashable {
        let bytes: [UInt8]
        let hashCache: Int

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            var h: UInt64 = 0xcbf29ce484222325
            for b in bytes {
                h = (h ^ UInt64(b)) &* 0x100000001b3
            }
            self.hashCache = Int(bitPattern: UInt(truncatingIfNeeded: h))
        }

        static func == (l: VocabKey, r: VocabKey) -> Bool {
            l.hashCache == r.hashCache && l.bytes == r.bytes
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(hashCache)
        }
    }

    private let pattern: NSRegularExpression?

    init() {
        // cl100k_base split pattern
        let patternStr = "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
        pattern = try? NSRegularExpression(pattern: patternStr, options: [])
        loadVocab()
    }

    private func loadVocab() {
        guard let url = Bundle.main.url(forResource: "cl100k_base", withExtension: "tiktoken"),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return
        }

        ranks.reserveCapacity(110_000)
        content.enumerateLines { line, _ in
            guard let sep = line.firstIndex(of: " ") else { return }
            let b64 = String(line[line.startIndex..<sep])
            let rankStr = line[line.index(after: sep)...]
            guard let tokenData = Data(base64Encoded: b64),
                  let rank = Int(rankStr) else { return }
            self.ranks[VocabKey([UInt8](tokenData))] = rank
        }
    }

    // MARK: - Counting

    func countTokens(_ text: String) -> Int {
        guard let pattern, !text.isEmpty else { return 0 }

        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        var total = 0
        var scratch = [UInt8]()
        scratch.reserveCapacity(256)

        pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let piece = nsText.substring(with: match.range)
            scratch.removeAll(keepingCapacity: true)
            scratch.append(contentsOf: piece.utf8)
            total += bpeCount(scratch)
        }

        return total
    }

    /// One node of the working list. `next`/`prev` form a doubly linked list over
    /// the byte ranges of `piece`, so a merge is O(1) and never reshuffles an array.
    private struct Node {
        var start: Int
        var end: Int      // exclusive
        var prev: Int
        var next: Int
        var alive: Bool
    }

    /// A pending merge of `index` with its right neighbour, valid only while
    /// that node's version still matches.
    private struct Candidate: Comparable {
        let rank: Int
        let index: Int
        let version: Int

        static func < (l: Candidate, r: Candidate) -> Bool {
            l.rank != r.rank ? l.rank < r.rank : l.index < r.index
        }
    }

    /// Merges `piece` down with the classic BPE rule (always merge the lowest-rank
    /// adjacent pair) and returns how many tokens remain.
    ///
    /// Unlike a naive rescan-every-round loop, each merge only re-scores the two
    /// pairs it actually disturbed, so cost is O(n log n) rather than O(n²).
    private func bpeCount(_ piece: [UInt8]) -> Int {
        let n = piece.count
        if n == 0 { return 0 }
        if n == 1 { return 1 }

        // Whole piece is a single known token — the common case for short words.
        if ranks[VocabKey(piece)] != nil { return 1 }

        var nodes = [Node]()
        nodes.reserveCapacity(n)
        for i in 0..<n {
            nodes.append(Node(start: i,
                              end: i + 1,
                              prev: i - 1,
                              next: i + 1 < n ? i + 1 : -1,
                              alive: true))
        }

        var versions = [Int](repeating: 0, count: n)
        var heap = MinHeap<Candidate>()
        heap.reserveCapacity(n)

        @inline(__always)
        func rankOfPair(_ i: Int) -> Int? {
            let j = nodes[i].next
            guard j != -1 else { return nil }
            let lo = nodes[i].start, hi = nodes[j].end
            return ranks[VocabKey(Array(piece[lo..<hi]))]
        }

        @inline(__always)
        func pushPair(_ i: Int) {
            guard i != -1, nodes[i].alive, let r = rankOfPair(i) else { return }
            heap.push(Candidate(rank: r, index: i, version: versions[i]))
        }

        for i in 0..<(n - 1) { pushPair(i) }

        var count = n

        while let top = heap.pop() {
            let i = top.index
            // Stale entry: this node was merged away or re-scored since it was queued.
            guard nodes[i].alive, versions[i] == top.version else { continue }
            let j = nodes[i].next
            guard j != -1, nodes[j].alive else { continue }

            // Absorb the right neighbour into i.
            nodes[i].end = nodes[j].end
            nodes[i].next = nodes[j].next
            if nodes[j].next != -1 {
                nodes[nodes[j].next].prev = i
            }
            nodes[j].alive = false
            count -= 1

            // Only i and its left neighbour changed shape.
            versions[i] += 1
            pushPair(i)

            let p = nodes[i].prev
            if p != -1 {
                versions[p] += 1
                pushPair(p)
            }
        }

        return count
    }
}

// MARK: - MinHeap

/// Minimal binary min-heap. Stdlib has no priority queue, and BPE needs one.
private struct MinHeap<Element: Comparable> {
    private var storage = [Element]()

    var isEmpty: Bool { storage.isEmpty }

    mutating func reserveCapacity(_ n: Int) {
        storage.reserveCapacity(n)
    }

    mutating func push(_ element: Element) {
        storage.append(element)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child] < storage[parent] else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard let first = storage.first else { return nil }
        let last = storage.removeLast()
        if !storage.isEmpty {
            storage[0] = last
            var parent = 0
            let count = storage.count
            while true {
                let left = parent * 2 + 1
                guard left < count else { break }
                let right = left + 1
                var smallest = left
                if right < count, storage[right] < storage[left] { smallest = right }
                guard storage[smallest] < storage[parent] else { break }
                storage.swapAt(smallest, parent)
                parent = smallest
            }
        }
        return first
    }
}
