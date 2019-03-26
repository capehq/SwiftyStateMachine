import Foundation

/// A type representing schema that can be reused by `StateMachine`
/// instances.
///
/// The schema incorporates three generic types: `State` and `Event`,
/// which should be `enum`s, and `Subject`, which represents an object
/// associated with a state machine.  If you don't want to associate any
/// object, use `Void` as `Subject` type.
///
/// The schema indicates the initial state and describes the transition
/// logic, i.e. how states are connected via events and what code is
/// executed during state transitions.  You specify transition logic
/// as a block that accepts two arguments: the current state and the
/// event being handled.  It returns an optional tuple of a new state
/// and an optional transition block.  When the tuple is `nil`, it
/// indicates that there is no transition for a given state-event pair,
/// i.e. a given event should be ignored in a given state.  When the
/// tuple is non-`nil`, it specifies the new state that the machine
/// should transition to and a block that should be called after the
/// transition.  The transition block is optional and it gets passed
/// the `Subject` object as an argument.
public protocol StateMachineSchemaType {
    associatedtype State
    associatedtype Event
    associatedtype Subject

    var initialState: State { get }
    var transitionLogic: (State, Event) -> (State, ((Subject) -> ())?)? { get }

    init(initialState: State, transitionLogic: @escaping (State, Event) -> (State, ((Subject) -> ())?)?) throws
}


/// A state machine schema conforming to the `StateMachineSchemaType`
/// protocol.  See protocol documentation for more information.
public struct StateMachineSchema<A, B, C>: StateMachineSchemaType {
    public typealias State = A
    public typealias Event = B
    public typealias Subject = C

    public let initialState: State
    public let transitionLogic: (State, Event) -> (State, ((Subject) -> ())?)?

    public init(initialState: State, transitionLogic: @escaping (State, Event) -> (State, ((Subject) -> ())?)?) throws {
        self.initialState = initialState
        self.transitionLogic = transitionLogic
    }
}


/// A state machine for a given schema, associated with a given subject.  See
/// `StateMachineSchemaType` documentation for more information about schemas
/// and subjects.
///
/// References to class-based subjects are weak.  This helps to remove 
/// subject-machine reference cycles, but it also means you have to keep a
/// strong reference to a subject somewhere else.  When subject references
/// become `nil`, transitions are no longer performed.
///
/// The state machine provides the `state` property for inspecting the current
/// state and the `handleEvent` method for triggering state transitions
/// defined in the schema.
///
/// To get notified about state changes, provide a `didTransitionCallback`
/// block.  It is called after a transition with three arguments:
/// the state before the transition, the event causing the transition,
/// and the state after the transition.
public final class StateMachine<Schema: StateMachineSchemaType> {
    /// The current state of the machine.  Note that state transitions are 
    /// _thread-safe_.  That means that the _state change_ and the _transition_
    /// are executed with a *write lock*.  Reading the state uses a *read lock*.
    /// This ensures that code executed in the state change happens _atomically_.
    public var state: Schema.State

    /// An optional block called after a transition with three arguments:
    /// the state before the transition, the event causing the transition,
    /// and the state after the transition.
    public var didTransitionCallback: ((Schema.State, Schema.Event, Schema.State) -> ())?

    /// An optional block called before a transition with the event about
    /// to be handled.
    public var aboutToHandleEventCallback: ((_ event: Schema.Event) -> ())?

    /// An optional block when transition logic in the schema returns nil.
    /// This could be useful for debugging or printing unexpected non-transitions.
    public var nilTransitionCallback: ((Schema.State, Schema.Event) -> ())?

    /// The schema of the state machine.  See `StateMachineSchemaType`
    /// documentation for more information.
    fileprivate let schema: Schema

    /// Object associated with the state machine.  Can be accessed in
    /// transition blocks.  Closure used to allow for weak references.
    fileprivate let subject: () -> Schema.Subject?

    /// If given, the queue in which all events are handled.  
    /// Otherwise they are handled in the thread in which handleEvent is called.
    fileprivate let queue: DispatchQueue?

    fileprivate init(schema: Schema, subject: @escaping () -> Schema.Subject?, queue: DispatchQueue? = nil) {
        self.state = schema.initialState
        self.schema = schema
        self.subject = subject
        self.queue = queue
    }
    
    /// A method for triggering transitions and changing the state of the
    /// machine.  Transitions are not performed when a weak reference to the subject
    /// becomes `nil`.  If the transition logic of the schema defines a transition
    /// for current state and given event, the state is changed, the optional
    /// transition block is executed, and `didTransitionCallback` is called.
    public func handleEvent(_ event: Schema.Event) {
        let `func` = {
                self.aboutToHandleEventCallback?(event)

                guard let subject = self.subject(),
                    let (newState, transition) = self.schema.transitionLogic(self.state, event)
                    else {
                        self.nilTransitionCallback?(self.state, event)
                        return
                }

                let oldState = self.state
                self.state = newState

                transition?(subject)

                self.didTransitionCallback?(oldState, event, newState)
        }
        if let queue = self.queue {
            queue.async {
                `func`()
            }
        } else {
            `func`()
        }
    }
}


public extension StateMachine where Schema.Subject: AnyObject {
    /// Creates a state machine with a weak reference to a subject.  This helps
    /// to remove subject-machine reference cycles, but it also means you have 
    /// to keep a strong reference to a subject somewhere else.  When subject 
    /// reference becomes `nil`, transitions are no longer performed.
    convenience init(schema: Schema, subject: Schema.Subject, queue: DispatchQueue? = nil) {
        self.init(schema: schema, subject: { [weak subject] in subject }, queue: queue)
    }
}

public extension StateMachine {
    convenience init(schema: Schema, subject: Schema.Subject, queue: DispatchQueue? = nil) {
        self.init(schema: schema, subject: { subject }, queue: queue)
    }
}

extension StateMachine: CustomDebugStringConvertible {
    public /// A textual representation of this instance, suitable for debugging.
    var debugDescription: String {
        return "\(Schema.State.self)Machine"
    }
}
