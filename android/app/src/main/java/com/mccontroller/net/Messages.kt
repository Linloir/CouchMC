package com.mccontroller.net

/**
 * Control messages received from the PC server (TCP channel only).
 */
sealed class ControlMessage

data class HelloAckMsg(val status: Byte, val udpPort: Int) : ControlMessage()
data class StateChangeMsg(val mode: Byte) : ControlMessage()
data class PongMsg(val seq: Int) : ControlMessage()
data class UnknownMsg(val type: Byte, val payloadLength: Int) : ControlMessage()
