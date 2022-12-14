//
//  Process.swift
//  _Architecture
//
//  Created by Ihor Malovanyi on 28.08.2022.
//

import Foundation

/// The `Process` is the object where your data performs.
/// It can contain workers, managers, network or database layers, etc...,
/// and use it for its work.
///
/// When you create an instance of `Process`, you create an object
/// with a special `State` and `Activity`.
///
/// Avoid the public properties inside the `Process`.
/// Use the `State` for accumulating all public data due to `Process` work.
///
/// Don't use the completions. Use the `perform` method instead.
/// The `perform` methods are built to notify the `Process`
/// listeners that some `Activity` started, finished, or received an error.
open class Process<State: ProcessState, Activity: ProcessActivity>: NSObject {
    
    //MARK: - Internal properties
    var recurciveLock: NSRecursiveLock = NSRecursiveLock()
    var runActivities: [Activity : UInt] = [:]
    var activityListenersMap: NSMapTable<AnyObject, ActivityListener> = .weakToStrongObjects()
    var stateListenersMap: NSMapTable<AnyKeyPath, NSMapTable<AnyObject, AnyStateListener>> = .weakToWeakObjects()
    var state: State = .entry
    var allActivityListeners: [ActivityListener] {
        (activityListenersMap.objectEnumerator()?.allObjects as? [ActivityListener]) ?? []
    }
    
//    lazy var queue = DispatchQueue(label: "pro.ihor.processqueue:\(type(of: self))")
    
    public var waiting: Bool { runActivities.isEmpty }
    public var runningActivities: Set<Activity> { Set(runActivities.keys) }
    
    //MARK: - Lifecycle
    
    ///Returns a new `Process` object.
    public override init() {
        super.init()
    }
    
    deinit {
        activityListenersMap.removeAllObjects()
        stateListenersMap.removeAllObjects()
    }
    
    //MARK: - State access
    ///Accesses the `State` element with the specified keyPath.
    ///
    ///The following example uses keyPath subscripting to update a process's state property `name`.
    ///After assigning the new value (`"Jack"`) by specific
    ///keyPath, that value will update immediately, than `Process` will notify all state listeners.
    ///
    ///     var userProcess = Process<UserState, UserActivity>()
    ///     userProcess[\.name] = "Jack"
    ///     print(userProcess[\.name])
    ///     // Prints "Jack"
    ///
    ///- Parameters:
    ///- keyPath: The keyPath of the `State` element to access. keyPath must corresponds to the `State`-contained property name.
    public subscript<T>(_ keyPath: WritableKeyPath<State, T>) -> T {
        get {
            state[keyPath: keyPath]
        }
        set {
            state[keyPath: keyPath] = newValue
            commitState(for: keyPath)
        }
    }
    
    public subscript<T>(_ keyPath: KeyPath<State, T>) -> T {
        state[keyPath: keyPath]
    }
    
    //MARK: - Internal methods
    
    func didStart(_ activity: Activity) {
        recurciveLock.lock()
        
        if !runningActivities.contains(activity) {
            commitActivity(.didStart(activity))
        }
        
        runActivities[activity, default: 0] += 1
        
        recurciveLock.unlock()
    }
    
    func didFinish(_ activity: Activity, error: Error?) {
        recurciveLock.lock()
        
        runActivities[activity, default: 0] -= 1
        
        if runActivities[activity] == 0 {
            runActivities[activity] = nil
            commitActivity(.didFinish(activity, error: error))
        }
        
        recurciveLock.unlock()
    }
    
    func commitActivity(_ event: Event) {
        allActivityListeners.forEach { $0.handler?(event) }
    }
    
    func commitState<T>(for keyPath: KeyPath<State, T>) {
        allStateListeners(for: keyPath).forEach { $0.handler?(state[keyPath: keyPath]) }
    }
    
    func allStateListeners<T>(for keyPath: KeyPath<State, T>) -> [StateListener<T>] {
        stateListenersMap.object(forKey: keyPath)?.objectEnumerator()?.allObjects.compactMap { $0 as? StateListener<T> } ?? []
    }
    
    //MARK: - Addition entities
    
    ///An activity event `Process` notifies.
    public enum Event {
        
        ///Notifies all process activity listeners that the specified activity has begun running.
        case didStart(Activity)
        
        ///Notifies all process activity listeners that the specified activity has finished running.
        case didFinish(Activity, error: Error?)
//        case didFinish(Activity)
        
        ///Notifies all process activity listeners that an error was received when the specified activity is running.
//        case receivedError(Activity, Error?)
        
        ///The event's activity.
        public var activity: Activity {
            switch self {
            case .didStart(let activity),
                    .didFinish(let activity, _):
                return activity
            }
        }
        
        ///The event's state.
        public var isFinished: Bool {
            if case .didFinish = self {
                return true
            }
            
            return false
        }
        
        ///The event's error.
        public var error: Error? {
            if case .didFinish(_, let error) = self {
                return error
            }
            
            return nil
        }
        
        public var hasError: Bool {
            error != nil
        }
        
    }

    class ActivityListener {
        
        final var handler: ((Event) -> ())?
        
    }
    
    
    class AnyStateListener {}
    class StateListener<T>: AnyStateListener {
        
        var handler: ((T) -> ())?
        
    }
    
}

//MARK: - Work with Listeners

public extension Process {
    
    ///Registers the listener object to receive activity events.
    ///
    ///- Parameters:
    ///     - object: The object to register for process activity listening.
    ///     - activityHandler: The handler receives the new activity event.
    func addActivityListener(_ object: AnyObject, _ activityHandler: @escaping (Event) -> ()) {
        let listener = activityListenersMap.object(forKey: object) ?? ActivityListener()
        listener.handler = activityHandler
        activityListenersMap.setObject(listener, forKey: object)
    }
    
    ///Stops the listener object from listening an activity events.
    ///
    ///- Parameters:
    ///     - object: The object to remove as an activity listener.
    func removeActivityListener(_ object: AnyObject) {
        activityListenersMap.removeObject(forKey: object)
    }
    
    ///Registers the listener object to observe the state changes
    ///for the key path relative to the state property updating.
    ///
    ///- Parameters:
    ///     - object: The object to register for process state listening.
    ///     - stateKeyPath: The key path, relative to the state property updating.
    ///     - updateHandler: The handler receives the new state value that it is observing.
    func addStateListener<T>(_ object: AnyObject, for stateKeyPath: KeyPath<State, T>, updateHandler: @escaping (T) -> ()) {
        if stateListenersMap.object(forKey: stateKeyPath) == nil {
            stateListenersMap.setObject(.weakToWeakObjects(), forKey: stateKeyPath)
        }
        
        let stateListener = StateListener<T>()
        stateListener.handler = updateHandler
       
        stateListenersMap.object(forKey: stateKeyPath)?.setObject(stateListener, forKey: object)
    }
    
    
    ///Stops the listener object from observing state changes for the property specified by the key path.
    ///
    ///- Parameters:
    ///     - object: The object to remove as an state listener.
    ///     - keyPath: A key-path, relative to the state property.
    func removeStateListener<T>(_ object: AnyObject, for stateKeyPath: KeyPath<State, T>) {
        stateListenersMap.object(forKey: stateKeyPath)?.removeObject(forKey: object)
        if stateListenersMap.object(forKey: stateKeyPath)?.count == 0 {
            stateListenersMap.removeObject(forKey: stateKeyPath)
        }
    }
    
}

//MARK: - Perform methods

public extension Process {
    
    ///Performs a block of code and catches possible errors.
    ///
    ///- Parameters:
    ///     - activity: The special activity label binds with the running block of code.
    ///     - work: The operation to perform.
    ///     - completion: The closure executes when the work is completed. Receives `true` when the work is completed successfully, and `false` if not.
    func perform(_ activity: Activity,
                              _ work: @escaping @Sendable () async throws -> (),
                              completion: ((Bool) -> ())? = nil) async throws {
        didStart(activity)
        do {
            try await work()
            completion?(true)
            didFinish(activity, error: nil)
        } catch {
            didFinish(activity, error: error)
            completion?(false)
        }
    }
    
    ///Performs a block of code and catches possible errors.
    ///
    ///- Parameters:
    ///     - activity: The activity label binds with the running block of code.
    ///     - priority: The priority of the task. Pass nil to use the priority from Task.currentPriority.
    ///     - work: The operation to perform.
    ///     - completion: The closure executes when the work is completed. Receives `true` when the work is completed successfully, and `false` if not.
    func perform(_ activity: Activity,
                              _ priority: TaskPriority? = nil,
                              _ work: @escaping @Sendable () async throws -> (),
                              completion: @escaping ((Bool) -> ()) = { _ in }) {
        
        Task(priority: priority) {
            try await perform(activity, work, completion: completion)
        }
    }
    
    ///Performs a block of code and catches possible errors.
    ///
    ///- Parameters:
    ///     - activity: The activity label binds with the running block of code.
    ///     - priority: The priority of the task. Pass nil to use the priority from Task.currentPriority.
    ///     - work: The operation to perform.
    ///     - completion: The closure executes when the work is completed. Receives `true` when the work is completed successfully, and `false` if not.
    func perform<T>(_ activity: Activity,
                        _ priority: TaskPriority? = nil,
                        _ work: @escaping (UnsafeContinuation<T, any Error>) -> (),
                        completion: ((Bool) -> ())? = nil) {
        Task(priority: priority) {
            try await perform(activity, work, completion: completion)
        }
    }
    
    ///Performs a block of code and catches possible errors.
    ///
    ///- Parameters:
    ///     - activity: The activity label binds with the running block of code.
    ///     - work: The operation to perform.
    ///     - completion: The closure executes when the work is completed. Receives `true` when the work is completed successfully, and `false` if not.
    func perform<T>(_ activity: Activity,
                           _ work: @escaping (UnsafeContinuation<T, any Error>) -> (),
                           completion: ((Bool) -> ())? = nil) async throws {
        didStart(activity)
        do {
            let _ = try await withUnsafeThrowingContinuation { continuation in
                work(continuation)
            }
            didFinish(activity, error: nil)
        } catch {
            didFinish(activity, error: error)
        }
    }
    
}
