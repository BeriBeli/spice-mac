import SpiceSessionLogic
import Testing

@Test func sessionStartsOnceAndCleansUpOnce() {
    var lifecycle = SessionLifecycle()

    let firstStart = lifecycle.start()
    let secondStart = lifecycle.start()
    #expect(firstStart)
    #expect(!secondStart)
    #expect(lifecycle.isActive)
    let firstStop = lifecycle.stop()
    #expect(firstStop)
    #expect(!lifecycle.isActive)
    let secondStop = lifecycle.stop()
    #expect(!secondStop)
}

@Test func terminalConnectionStateReturnsToLauncherButWindowCloseDoesNot() {
    for _ in ["disconnected", "failed"] {
        var terminalSession = SessionLifecycle()
        let started = terminalSession.start()
        let shouldReturn = terminalSession.connectionDidTerminate()
        #expect(started)
        #expect(shouldReturn)
    }

    var windowClose = SessionLifecycle()
    let localStarted = windowClose.start()
    let localStopped = windowClose.stop()
    let shouldNotReturn = windowClose.connectionDidTerminate()
    #expect(localStarted)
    #expect(localStopped)
    #expect(!shouldNotReturn)
}

@Test func sessionCommandsRequireFocusedInput() {
    let noSession = SessionCommandAvailability(hasActiveSession: false, hasInput: false)
    let connecting = SessionCommandAvailability(hasActiveSession: true, hasInput: false)
    let interactive = SessionCommandAvailability(hasActiveSession: true, hasInput: true)

    #expect(!noSession.canSendCtrlAltDelete)
    #expect(!noSession.canReleaseCursor)
    #expect(!connecting.canSendCtrlAltDelete)
    #expect(!connecting.canReleaseCursor)
    #expect(interactive.canSendCtrlAltDelete)
    #expect(interactive.canReleaseCursor)
}
