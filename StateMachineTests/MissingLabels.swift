//
//  EventsWithPayloadTests.swift
//  SwiftyStateMachine
//
//  Created by Rick Pasetto on 4/7/17.
//  Copyright © 2017 Macoscope. All rights reserved.
//

import XCTest
import SwiftyStateMachine

enum Letter {
    case a, b, c
}

enum Move {
    case forward(n: Int), backward(why: String)
}

extension Letter: DOTLabelable {
    static var DOTLabelableItems: [Letter] {
        return [.a, .b] // missing c!
    }
}

extension Move: DOTLabelable {
    static var DOTLabelableItems: [Move] {
        return [.forward(n: 1), .backward(why: "cuz!")]
    }
}

typealias MySchema = GraphableStateMachineSchema<Letter, Move, Void>
typealias MyStateMachine = StateMachine<MySchema>

class MissingLabels: XCTestCase {

    func testWithMissingLabels() {

        // TODO: Do this better with XCTAssertThrowsError of type
        var thrownError: Error? = nil
        do {
            let schema = try MySchema(initialState: .a) { (state, event) in
                switch state {
                case .a:
                    switch event {
                    case .backward: return nil
                    case .forward: return (.b, { _ in print("a → b") })
                    }
                case .b:
                    switch event {
                    case .backward: return (.a, { _ in print("b → a") })
                    case .forward: return (.c, { _ in print("b → c") })
                    }

                case .c:
                    switch event {
                    case .backward: return (.b, nil)  // nil transition block
                    case .forward: return nil
                    }
                }
            }
            print(schema.DOTDigraph)
        }
        catch {
            print("Error: \(error)")
            thrownError = error
        }
        XCTAssertNotNil(thrownError)

    }

}
