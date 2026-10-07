// Compile against RachelEngine; see specs/engine-transitions-v1.md.
import Foundation
import RachelEngine

let source = "2dd624a8c4d394c3bc86d61316ab936fe4917c33"
func card(_ suit: Suit, _ rank: Rank) -> Card { Card(suit: suit, rank: rank) }
func list<T>(_ values: [T]) -> String { values.isEmpty ? "-" : values.map { String(describing: $0) }.joined(separator: ",") }
func cards(_ values: [Card]) -> String { list(values.map(\.encoded)) }
func vector(_ state: GameState) -> String {
    let snapshot = StateSnapshot(state: state)
    return [
        cards(state.deck), cards(state.discardPile), state.players.map { cards($0.hand) }.joined(separator: "/"),
        String(state.currentPlayerIndex), state.direction == .clockwise ? "1" : "-1",
        String(state.pendingDraws), String(state.pendingSkips), state.nominatedSuit.map { String($0.rawValue) } ?? "-1",
        list(state.players.map { $0.isOut ? 1 : 0 }), list(snapshot.finishOrder), String(state.turnNumber), String(state.randomSeed),
        list(state.attackHistory.map { "\($0.attackerIndex):\($0.targetIndex):\($0.severity):\($0.turn)" }),
    ].joined(separator: ";")
}
var rows: [String] = []
func emit(_ id: String, _ state: GameState, _ action: GameAction) throws {
    var kind = "draw", played = "-", nomination = "-1"
    if case let .play(values, suit) = action {
        kind = "play"; played = cards(values); nomination = suit.map { String($0.rawValue) } ?? "-1"
    }
    let after: GameState
    let outcome: String
    do { after = try GameEngine.process(action: action, in: state); outcome = "ok" }
    catch let error as GameError { after = state; outcome = error.specIdentifier }
    if id.hasPrefix("seats-") {
        precondition(outcome == "ok", "Multiplayer action unexpectedly rejected: \(id)")
        for snapshot in [state, after] {
            let allCards = snapshot.deck + snapshot.discardPile + snapshot.players.flatMap(\.hand)
            precondition(allCards.count == 52 && Set(allCards).count == 52, "Invalid deck in \(id)")
        }
    }
    rows.append([id, kind, played, nomination, outcome, vector(state), vector(after),
                 String(GameStateHasher.hash(state)), String(GameStateHasher.hash(after))].joined(separator: "\t"))
}
func state(_ top: Card, _ hand: [Card], opponent: [Card] = [card(.clubs, .king)], draws: Int = 0, skips: Int = 0) -> GameState {
    let used = Set(hand + opponent + [top])
    return GameState(deck: Deck.standard().filter { !used.contains($0) }, discardPile: [top],
                     players: [Player(name: "user_a", hand: hand), Player(name: "user_b", hand: opponent)],
                     pendingDraws: draws, pendingSkips: skips, turnNumber: 9, randomSeed: 42)
}
let filler = card(.diamonds, .nine)
let five = card(.hearts, .five)
func play(_ id: String, top: Card = five, values: [Card], draws: Int = 0, skips: Int = 0, suit: Suit? = nil,
          opponent: [Card] = [card(.clubs, .king)], finish: Bool = false) throws {
    try emit(id, state(top, values + (finish ? [] : [filler]), opponent: opponent, draws: draws, skips: skips),
             .play(cards: values, nominatedSuit: suit))
}
try play("ordinary-play", values: [card(.hearts, .nine)])
try play("ordinary-stack", values: [card(.hearts, .four), card(.clubs, .four)])
try play("two-attack", values: [card(.hearts, .two)])
try play("two-stack", values: [card(.hearts, .two), card(.clubs, .two)])
try play("two-counter", top: card(.spades, .two), values: [card(.hearts, .two)], draws: 4)
try play("black-jack-attack", top: card(.spades, .five), values: [card(.spades, .jack)])
try play("black-jack-stack", top: card(.spades, .five), values: [card(.spades, .jack), card(.clubs, .jack)])
try play("black-jack-counter", top: card(.spades, .jack), values: [card(.clubs, .jack)], draws: 5)
try play("red-jack-cancel", top: card(.spades, .jack), values: [card(.hearts, .jack)], draws: 5)
try play("red-jack-reduce", top: card(.spades, .jack), values: [card(.hearts, .jack)], draws: 10)
try play("red-jack-normal", values: [card(.hearts, .jack)])
try play("mixed-jack-stack", top: card(.spades, .jack), values: [card(.clubs, .jack), card(.hearts, .jack)], draws: 5)
try play("queen-reverse", values: [card(.hearts, .queen)])
try play("queen-double-reverse", values: [card(.hearts, .queen), card(.clubs, .queen)])
try play("ace-nominate", values: [card(.hearts, .ace)], suit: .spades)
try play("ace-stack", values: [card(.hearts, .ace), card(.clubs, .ace)], suit: .diamonds)
try play("seven-skips-opponent", values: [card(.hearts, .seven)])
try play("seven-stops-at-counter", values: [card(.hearts, .seven)], opponent: [card(.clubs, .seven), card(.clubs, .king)])
try play("seven-stack-wraps", values: [card(.hearts, .seven), card(.clubs, .seven)])
try play("seven-counter", top: card(.spades, .seven), values: [card(.hearts, .seven)], skips: 1)
try play("finish-ordinary", values: [card(.hearts, .nine)], finish: true)
try play("finish-queen", values: [card(.hearts, .queen)], finish: true)
try play("finish-seven", values: [card(.hearts, .seven)], finish: true)
try play("finish-two", values: [card(.hearts, .two)], finish: true)
var nominated = state(card(.hearts, .ace), [card(.clubs, .four), filler])
nominated.nominatedSuit = .clubs
try emit("follow-nomination", nominated, .play(cards: [card(.clubs, .four)], nominatedSuit: nil))
try emit("reject-old-suit", nominated, .play(cards: [filler], nominatedSuit: nil))
try emit("ordinary-draw", state(five, [card(.clubs, .three)]), .draw)
try emit("draw-two-penalty", state(card(.hearts, .two), [filler], draws: 4), .draw)
try emit("draw-jack-penalty", state(card(.spades, .jack), [filler], draws: 10), .draw)
try emit("draw-red-jack-residue", state(card(.hearts, .jack), [card(.clubs, .jack), filler], draws: 5), .draw)
for (id, deckCount, seed) in [("reshuffle-empty", 0, UInt64(42)), ("reshuffle-partway", 2, UInt64(42)), ("reshuffle-zero-seed", 0, UInt64(0))] {
    var exhausted = state(card(.hearts, .two), [filler], draws: 5)
    exhausted.discardPile = Array(exhausted.deck.dropFirst(deckCount)) + exhausted.discardPile
    exhausted.deck = Array(exhausted.deck.prefix(deckCount))
    exhausted.randomSeed = seed
    try emit(id, exhausted, .draw)
}
var insufficient = state(card(.hearts, .two), [filler], draws: 5)
insufficient.deck = [card(.clubs, .three)]
try emit("draw-insufficient-cards", insufficient, .draw)
try emit("reject-ordinary-draw", state(five, [card(.hearts, .nine)]), .draw)
for (id, top, counter, draws, skips) in [
    ("two", card(.hearts, .two), card(.clubs, .two), 2, 0),
    ("black-jack", card(.spades, .jack), card(.clubs, .jack), 5, 0),
    ("red-jack", card(.spades, .jack), card(.hearts, .jack), 10, 0),
    ("seven", card(.hearts, .seven), card(.clubs, .seven), 0, 2),
] { try emit("reject-draw-with-\(id)", state(top, [counter, filler], draws: draws, skips: skips), .draw) }
try play("reject-ace-without-nomination", values: [card(.hearts, .ace)])
try play("reject-non-ace-nomination", values: [card(.hearts, .nine)], suit: .clubs)
let held = card(.hearts, .nine)
try emit("reject-duplicate-card", state(five, [held, filler]), .play(cards: [held, held], nominatedSuit: nil))
try emit("reject-absent-card", state(five, [held, filler]), .play(cards: [card(.hearts, .king)], nominatedSuit: nil))
try emit("reject-mixed-rank", state(five, [held, card(.hearts, .king)]), .play(cards: [held, card(.hearts, .king)], nominatedSuit: nil))
try emit("reject-empty-play", state(five, [held, filler]), .play(cards: [], nominatedSuit: nil))
var finished = state(five, [], opponent: [card(.clubs, .five)])
finished.players[0].isOut = true
finished.finishOrder = [finished.players[0].id]
finished.currentPlayerIndex = 1
try emit("reject-play-after-finish", finished, .play(cards: [card(.clubs, .five)], nominatedSuit: nil))
finished.players[1].hand = [card(.clubs, .three)]
try emit("reject-draw-after-finish", finished, .draw)
for seed: UInt64 in [7, 42] {
    var game = try GameEngine.newGame(playerNames: ["user_a", "user_b"], seed: seed)
    for turn in 0..<500 {
        if game.isGameOver { break }
        let action: GameAction
        if let lead = PlayValidator.validCards(in: game).first {
            let stack = [lead] + game.currentPlayer.hand.filter { $0 != lead && $0.rank == lead.rank }
            action = .play(cards: stack, nominatedSuit: lead.rank == .ace ? .hearts : nil)
        } else { action = .draw }
        try emit("seed-\(seed)-turn-\(turn)", game, action)
        game = try GameEngine.process(action: action, in: game)
    }
    precondition(game.isGameOver, "Seeded replay failed to finish")
}
// Exercise turn advancement across eliminated seats in both directions,
// including the final transition when only a nonadjacent survivor remains.
for count in 3...8 {
    for direction in [Direction.clockwise, .counterClockwise] {
        let sign = direction == .clockwise ? 1 : -1
        for rank in [Rank.nine, .two, .seven, .queen] {
            for finish in [false, true] {
                let effectiveSign = rank == .queen ? -sign : sign
                let neighbor = (effectiveSign + count) % count
                let survivor = (count - effectiveSign) % count
                let played = card(.hearts, rank)
                let otherRanks: [Rank] = [.three, .four, .five, .six, .eight, .nine, .ten]
                var players = (0..<count).map { seat in
                    Player(name: "user_\(seat)", hand: seat == 0 ? [played] + (finish ? [] : [filler]) : [card(.spades, otherRanks[seat - 1])])
                }
                for seat in 1..<count where finish ? seat != survivor : seat == neighbor {
                    players[seat].hand = []
                    players[seat].isOut = true
                }
                let used = Set(players.flatMap(\.hand) + [five])
                let game = GameState(deck: Deck.standard().filter { !used.contains($0) }, discardPile: [five],
                                     players: players, direction: direction,
                                     finishOrder: players.filter(\.isOut).map(\.id), turnNumber: 9, randomSeed: 42)
                try emit("seats-\(count)-direction-\(sign)-\(rank.rawValue)-\(finish ? "finish" : "advance")",
                         game, .play(cards: [played], nominatedSuit: nil))
            }
        }
        // A seven holder beyond an eliminated seat must get the chance to counter.
        let neighbor = (sign + count) % count
        let target = (2 * sign + count) % count
        var players = (0..<count).map { seat in Player(name: "user_\(seat)", hand: [card(.spades, .king)]) }
        players[0].hand = [card(.hearts, .seven), filler]
        players[neighbor].hand = []
        players[neighbor].isOut = true
        players[target].hand = [card(.clubs, .seven), card(.clubs, .king)]
        // Give other active seats distinct cards, retaining one physical deck.
        for seat in 1..<count where seat != neighbor && seat != target {
            let ranks: [Rank] = [.two, .three, .four, .five, .six, .seven, .eight, .nine]
            players[seat].hand = [card(.spades, ranks[seat])]
        }
        let used = Set(players.flatMap(\.hand) + [five])
        let game = GameState(deck: Deck.standard().filter { !used.contains($0) }, discardPile: [five], players: players,
                             direction: direction, finishOrder: [players[neighbor].id], turnNumber: 9, randomSeed: 42)
        try emit("seats-\(count)-direction-\(sign)-seven-counter-past-out", game,
                 .play(cards: [card(.hearts, .seven)], nominatedSuit: nil))
    }
    for seed: UInt64 in [7, 42] {
        var game = try GameEngine.newGame(playerNames: (0..<count).map { "user_\($0)" }, seed: seed)
        for turn in 0..<1000 {
            if game.isGameOver { break }
            let action: GameAction
            if let lead = PlayValidator.validCards(in: game).first {
                let stack = [lead] + game.currentPlayer.hand.filter { $0 != lead && $0.rank == lead.rank }
                action = .play(cards: stack, nominatedSuit: lead.rank == .ace ? .hearts : nil)
            } else { action = .draw }
            try emit("seats-\(count)-seed-\(seed)-turn-\(turn)", game, action)
            game = try GameEngine.process(action: action, in: game)
        }
        precondition(game.isGameOver && game.finishOrder.count == count - 1, "Multiplayer replay failed to finish")
    }
}
print("# engine-transitions-v1; RachelEngine source \(source)")
print("# id\taction\tcards\tnomination\toutcome\tbefore\tafter\tbeforeHash\tafterHash")
print(rows.joined(separator: "\n"))
