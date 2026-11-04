package it.italic.italicapp

import org.junit.Assert.*
import org.junit.Test

class GnssFixPolicyTest {
    @Test fun preciseCoordinatesWithoutAltitudeMustKeepWaiting() {
        assertFalse(GnssFixPolicy.ready(GnssQuality(2f, false, null), 0))
        assertFalse(GnssFixPolicy.ready(GnssQuality(2f, false, null), 4))
    }
    @Test fun laterAltitudeIsNotDiscardedForASlightlyWorseHorizontalFix() {
        assertTrue(GnssFixPolicy.prefer(GnssQuality(5f, true, 8f), GnssQuality(3f, false, null)))
        assertFalse(GnssFixPolicy.prefer(GnssQuality(2f, false, null), GnssQuality(5f, true, 8f)))
        assertTrue(GnssFixPolicy.ready(GnssQuality(5f, true, 8f), 2))
        assertFalse(GnssFixPolicy.ready(GnssQuality(5f, true, 8f), 1))
    }
    @Test fun altitudeDoesNotOverrideAnUnreasonablyPoorPosition() {
        assertFalse(GnssFixPolicy.prefer(GnssQuality(150f, true, 8f), GnssQuality(3f, false, null)))
        assertTrue(GnssFixPolicy.prefer(GnssQuality(6f, true, 4f), GnssQuality(5f, true, 12f)))
    }
}
