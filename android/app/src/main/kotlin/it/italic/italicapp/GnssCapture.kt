package it.italic.italicapp

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.core.location.LocationCompat
import androidx.core.location.altitude.AltitudeConverterCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Fresh satellite fixes only; raw ellipsoid and sea-level altitudes stay distinct. */
class GnssCapture(context: Context) {
    private val app = context.applicationContext
    private val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var best: Location? = null
    private var samples = 0
    private var satellites: Int? = null
    private var listener: LocationListener? = null
    private var status: GnssStatus.Callback? = null
    private val timeout = Runnable { finish() }

    fun capture(result: MethodChannel.Result) {
        if (pending != null) { result.error("GPS_BUSY", "Una misura GPS è già in corso.", null); return }
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PRECISE_REQUIRED", "Abilita la posizione precisa per Italicapp nelle impostazioni del telefono.", null); return
        }
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            result.error("GPS_DISABLED", "Attiva il GPS del telefono e riprova.", null); return
        }
        pending = result; best = null; samples = 0; satellites = null
        status = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(value: GnssStatus) {
                satellites = (0 until value.satelliteCount).count { value.usedInFix(it) }
            }
        }
        listener = object : LocationListener {
            override fun onLocationChanged(value: Location) {
                val age = (SystemClock.elapsedRealtimeNanos() - value.elapsedRealtimeNanos) / 1e9
                if (age < 0 || age > 30 || !value.latitude.isFinite() || !value.longitude.isFinite() ||
                    !value.hasAccuracy() || !value.accuracy.isFinite() || value.accuracy <= 0) return
                samples++
                if (best == null || value.accuracy <= best!!.accuracy) best = Location(value)
                if (samples >= 2 && best!!.accuracy <= 10f) finish()
            }
            override fun onProviderDisabled(provider: String) { finish() }
            override fun onProviderEnabled(provider: String) {}
            @Deprecated("Legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            manager.registerGnssStatusCallback(status!!, handler)
            manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, listener!!, Looper.getMainLooper())
            handler.postDelayed(timeout, 35000L)
        } catch (_: Exception) {
            cleanup(); pending = null
            result.error("GPS_UNAVAILABLE", "GPS non disponibile. Controlla i permessi e riprova all’aperto.", null)
        }
    }

    private fun cleanup() {
        handler.removeCallbacks(timeout)
        listener?.let { manager.removeUpdates(it) }; listener = null
        status?.let { manager.unregisterGnssStatusCallback(it) }; status = null
    }

    private fun finish() {
        val result = pending ?: return
        pending = null; cleanup()
        val fix = best
        val used = satellites
        if (fix == null) { result.error("GPS_TIMEOUT", "Nessuna posizione satellitare recente. Spostati all’aperto e riprova.", null); return }
        worker.execute {
            val ellipsoid = if (fix.hasAltitude() && fix.altitude.isFinite()) fix.altitude else null
            var source: String? = null
            if (ellipsoid != null) {
                try {
                    if (LocationCompat.hasMslAltitude(fix)) source = "Android MSL"
                    else { AltitudeConverterCompat.addMslAltitudeToLocation(app, fix); source = "AndroidX geoid" }
                } catch (_: Exception) { source = null }
            }
            val msl = if (source != null && LocationCompat.hasMslAltitude(fix)) LocationCompat.getMslAltitudeMeters(fix) else null
            val vertical = if (msl != null && LocationCompat.hasMslAltitudeAccuracy(fix)) LocationCompat.getMslAltitudeAccuracyMeters(fix).toDouble() else null
            val data = mapOf("latitude" to fix.latitude, "longitude" to fix.longitude,
                "accuracy" to fix.accuracy.toDouble(), "timestamp" to fix.time,
                "ellipsoidAltitude" to ellipsoid, "seaLevelAltitude" to msl,
                "altitudeAccuracy" to vertical, "altitudeSource" to source,
                "provider" to "gps", "satellitesUsed" to used,
                "mocked" to LocationCompat.isMock(fix))
            handler.post { result.success(data) }
        }
    }

    fun cancel() { val result = pending; pending = null; cleanup(); result?.error("CANCELLED", "Misura annullata.", null) }
    fun close() { cancel(); worker.shutdown() }
}
