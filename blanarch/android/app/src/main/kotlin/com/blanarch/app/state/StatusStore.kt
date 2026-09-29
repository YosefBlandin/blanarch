package com.blanarch.app.state

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Single source of truth for connection status and the activity log.
 * Status updates are atomic copies, so readers never see a half-written state.
 * Never pass secrets to [log].
 */
class StatusStore(private val clock: () -> Long = System::currentTimeMillis, private val logCapacity: Int = 200) {
    private val _status = MutableStateFlow(VpnStatus())
    val status: StateFlow<VpnStatus> = _status.asStateFlow()

    private val entries = ArrayDeque<LogEntry>()
    private val _log = MutableSharedFlow<LogEntry>(extraBufferCapacity = 64)
    val log: SharedFlow<LogEntry> = _log.asSharedFlow()

    fun update(transform: (VpnStatus) -> VpnStatus) = _status.update(transform)

    fun log(
        message: String,
        level: LogLevel = LogLevel.INFO,
        event: LogEvent? = null,
        args: List<String> = emptyList()
    ) {
        val entry = LogEntry(clock(), level, message, event, args)
        synchronized(entries) {
            entries.addLast(entry)
            while (entries.size > logCapacity) entries.removeFirst()
        }
        _log.tryEmit(entry)
    }

    fun logSnapshot(): List<LogEntry> = synchronized(entries) { entries.toList() }
}
