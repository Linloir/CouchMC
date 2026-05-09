package com.mccontroller.net

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Stateless encode/decode for the wire protocol. All multi-byte fields are big-endian.
 *
 * TCP frame: [u16 len][u8 type][payload (len-1 bytes)]
 * UDP datagram: [u8 type][u32 seq][payload]
 */
object PacketCodec {

    data class FrameRead(val frameLen: Int, val msg: ControlMessage)

    // ===== Outgoing =====

    fun encodeHello(protoVer: Byte, clientId: Int, wantsUdp: Boolean): ByteArray {
        // payload: protoVer(1) + clientId(4) + wantsUdp(1) = 6 bytes
        val buf = ByteBuffer.allocate(2 + 1 + 6).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((1 + 6).toShort())
        buf.put(Protocol.MsgType.HELLO)
        buf.put(protoVer)
        buf.putInt(clientId)
        buf.put(if (wantsUdp) 1 else 0)
        return buf.array()
    }

    fun encodeJoystick(x: Float, y: Float): ByteArray {
        val ix = (x * 10000f).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        val iy = (y * 10000f).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        val buf = ByteBuffer.allocate(2 + 1 + 4).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((1 + 4).toShort())
        buf.put(Protocol.MsgType.JOYSTICK)
        buf.putShort(ix)
        buf.putShort(iy)
        return buf.array()
    }

    fun encodeButton(buttonId: Byte, down: Boolean): ByteArray {
        val buf = ByteBuffer.allocate(2 + 1 + 2).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((1 + 2).toShort())
        buf.put(Protocol.MsgType.BUTTON)
        buf.put(buttonId)
        buf.put(if (down) 1 else 0)
        return buf.array()
    }

    fun encodePing(seq: Int): ByteArray {
        val buf = ByteBuffer.allocate(2 + 1 + 4).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((1 + 4).toShort())
        buf.put(Protocol.MsgType.PING)
        buf.putInt(seq)
        return buf.array()
    }

    fun encodeLookDeltaUdp(seq: Int, dx: Short, dy: Short): ByteArray {
        // No length prefix; UDP datagram boundary is the frame.
        val buf = ByteBuffer.allocate(1 + 4 + 4).order(ByteOrder.BIG_ENDIAN)
        buf.put(Protocol.MsgType.LOOK_DELTA_UDP)
        buf.putInt(seq)
        buf.putShort(dx)
        buf.putShort(dy)
        return buf.array()
    }

    fun encodeLookDeltaTcp(seq: Int, dx: Short, dy: Short): ByteArray {
        val buf = ByteBuffer.allocate(2 + 1 + 8).order(ByteOrder.BIG_ENDIAN)
        buf.putShort((1 + 8).toShort())
        buf.put(Protocol.MsgType.LOOK_DELTA_TCP)
        buf.putInt(seq)
        buf.putShort(dx)
        buf.putShort(dy)
        return buf.array()
    }

    // ===== Incoming TCP framing =====

    /**
     * Parse one frame starting at `buffer[start]`, with valid bytes up to `end`.
     * Returns null if the buffer doesn't yet contain a complete frame.
     */
    fun tryReadFrame(buffer: ByteArray, start: Int, end: Int): FrameRead? {
        val available = end - start
        if (available < 3) return null  // need len(2) + type(1)

        val len = ((buffer[start].toInt() and 0xFF) shl 8) or (buffer[start + 1].toInt() and 0xFF)
        if (len < 1) return null
        if (available < 2 + len) return null

        val type = buffer[start + 2]
        val payloadStart = start + 3
        val payloadLen = len - 1

        val msg: ControlMessage = when (type) {
            Protocol.MsgType.HELLO_ACK -> {
                if (payloadLen >= 3) {
                    val status = buffer[payloadStart]
                    val udpPort = ((buffer[payloadStart + 1].toInt() and 0xFF) shl 8) or
                            (buffer[payloadStart + 2].toInt() and 0xFF)
                    HelloAckMsg(status, udpPort)
                } else UnknownMsg(type, payloadLen)
            }
            Protocol.MsgType.PONG -> {
                if (payloadLen >= 4) {
                    val seq = readInt32BE(buffer, payloadStart)
                    PongMsg(seq)
                } else UnknownMsg(type, payloadLen)
            }
            else -> UnknownMsg(type, payloadLen)
        }
        return FrameRead(2 + len, msg)
    }

    private fun readInt32BE(buffer: ByteArray, offset: Int): Int {
        return ((buffer[offset].toInt() and 0xFF) shl 24) or
                ((buffer[offset + 1].toInt() and 0xFF) shl 16) or
                ((buffer[offset + 2].toInt() and 0xFF) shl 8) or
                (buffer[offset + 3].toInt() and 0xFF)
    }
}
