package it.italic.italicapp

/** Prefer a valid 3-D fix; horizontal precision alone cannot finish altitude capture. */
internal data class GnssQuality(val horizontal: Float, val altitude: Boolean, val vertical: Float?)

internal object GnssFixPolicy {
    fun prefer(candidate: GnssQuality, current: GnssQuality?): Boolean {
        if (current == null) return true
        if (candidate.altitude != current.altitude) {
            return if (candidate.altitude) candidate.horizontal <= maxOf(30f, current.horizontal * 2)
            else current.horizontal > maxOf(30f, candidate.horizontal * 2)
        }
        if (candidate.altitude && candidate.horizontal <= maxOf(15f, current.horizontal * 1.5f)) {
            val cv = candidate.vertical
            val bv = current.vertical
            if (cv != null && (bv == null || cv < bv)) return true
        }
        return candidate.horizontal <= current.horizontal
    }

    fun ready(quality: GnssQuality, altitudeSamples: Int): Boolean =
        quality.altitude && quality.horizontal <= 10f && altitudeSamples >= 2
}
