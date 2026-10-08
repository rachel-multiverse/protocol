// Compile against a fresh RachelEngine build; see specs/engine-setups-v1.md.
import RachelEngine

let source = "dce77031bf6a4c49bc3b6780abd89254b88a8f97"
let seeds: [UInt64] = [0, 7, 11, 42, .max]
// Approved inherited rule, deliberately independent of cardsPerPlayer(for:).
let handSizes = [2: 7, 3: 7, 4: 7, 5: 7, 6: 6, 7: 5, 8: 5]
func list<T>(_ values: [T]) -> String {
    values.isEmpty ? "-" : values.map { String(describing: $0) }.joined(separator: ",")
}
func cards(_ values: [Card]) -> String { list(values.map(\.encoded)) }
var rows: [String] = []
var openingCards = Set<Card>()
for seats in 2 ... 8 {
    for seed in seeds {
        let state = try GameEngine.newGame(playerNames: (0 ..< seats).map { "user_\($0)" }, seed: seed)
        let snapshot = StateSnapshot(state: state)
        let allCards = state.deck + state.discardPile + state.players.flatMap(\.hand)
        precondition(allCards.count == 52 && Set(allCards) == Set(Deck.standard()))
        precondition(state.players.count == seats && state.players.allSatisfy { $0.hand.count == handSizes[seats] && !$0.isOut })
        precondition(state.deck.count >= 10 && state.discardPile.count == 1)
        precondition(state.currentPlayerIndex == 0 && state.direction == .clockwise && state.turnNumber == 0)
        precondition(state.pendingDraws == 0 && state.pendingSkips == 0 && state.nominatedSuit == nil)
        precondition(snapshot.finishOrder.isEmpty && state.attackHistory.isEmpty)
        openingCards.formUnion(state.discardPile)
        let fields = [
            cards(state.deck), cards(state.discardPile), state.players.map { cards($0.hand) }.joined(separator: "/"),
            String(state.currentPlayerIndex), state.direction == .clockwise ? "1" : "-1",
            String(state.pendingDraws), String(state.pendingSkips), state.nominatedSuit.map { String($0.rawValue) } ?? "-1",
            list(state.players.map { $0.isOut ? 1 : 0 }), list(snapshot.finishOrder), String(state.turnNumber),
            String(state.randomSeed), list(state.attackHistory.map { "\($0.attackerIndex):\($0.targetIndex):\($0.severity):\($0.turn)" }),
        ].joined(separator: ";")
        rows.append(["seats-\(seats)-seed-\(seed)", String(seats), String(seed), fields,
                     String(GameStateHasher.hash(state))].joined(separator: "\t"))
    }
}
precondition(rows.count == 35)
precondition(Set(openingCards.map(\.rank)) == Set(Rank.allCases))
precondition(openingCards.contains(where: \.isBlackJack) && openingCards.contains(where: \.isRedJack))
// Print only after all invariants pass; a failed generator must not publish a partial pack.
print("# engine-setups-v1; RachelEngine source \(source)")
print("# id\tseats\tseed\tstate\tstateHash")
print(rows.joined(separator: "\n"))
