package com.example.music_player

import android.content.Intent
import android.os.Build
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.content.Context

import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import android.content.ContentValues
import android.media.MediaScannerConnection
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
	private val channelName = "com.example.music_player/notifications"
	private val mediaStoreChannelName = "com.example.music_player/media_store"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val nm = getSystemService(android.app.NotificationManager::class.java)
			try {
				nm?.deleteNotificationChannel("com.example.music_player.channel.audio")
			} catch (_: Exception) {}

			val channelId = "com.example.music_player.channel.audio.v2"
			val existing = nm?.getNotificationChannel(channelId)
			if (existing == null) {
				val channel = android.app.NotificationChannel(
					channelId,
					"Music playback",
					android.app.NotificationManager.IMPORTANCE_LOW
				).apply {
					description = "Playback controls and track information"
					setShowBadge(false)
					setSound(null, null)
					enableVibration(false)
					vibrationPattern = null
				}
				nm?.createNotificationChannel(channel)
			}
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"areNotificationsEnabled" -> {
					val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
					result.success(enabled)
				}
				"getChannelImportance" -> {
					val channelId = call.argument<String>("channelId")
					if (channelId == null) {
						result.error("bad_args", "channelId is required", null)
						return@setMethodCallHandler
					}
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
						val nm = getSystemService(android.app.NotificationManager::class.java)
						val channel = nm.getNotificationChannel(channelId)
						result.success(channel?.importance)
					} else {
						result.success(null)
					}
				}
				"openAppNotificationSettings" -> {
					val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
						putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
						addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
					}
					startActivity(intent)
					result.success(true)
				}
				"openChannelNotificationSettings" -> {
					val channelId = call.argument<String>("channelId")
					if (channelId == null) {
						result.error("bad_args", "channelId is required", null)
						return@setMethodCallHandler
					}
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
						val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
							putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
							putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
							addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(intent)
						result.success(true)
					} else {
						val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
							putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
							addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(intent)
						result.success(true)
					}
				}
				"setSpeakerphoneOn" -> {
					val on = call.argument<Boolean>("on") ?: false
					val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
					am.isSpeakerphoneOn = on
					result.success(true)
				}
				"getAvailableAudioDevices" -> {
					val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
					val resultList = mutableListOf<Map<String, Any>>()
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
						val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
						val currentCommDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
							try { am.communicationDevice } catch (_: Exception) { null }
						} else null

						for (d in devices) {
							val isBt = d.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
									d.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
									d.type == 26 || // TYPE_BLE_HEADSET
									d.type == 27 || // TYPE_BLE_SPEAKER
									d.type == 30    // TYPE_BLE_BROADCAST

							val isSpeaker = d.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
									(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && d.type == 24) // TYPE_BUILTIN_SPEAKER_SAFE

							val isHeadphones = d.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
									d.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
									d.type == AudioDeviceInfo.TYPE_USB_HEADSET

							val typeLabel = when {
								isBt -> "Bluetooth Audio"
								isSpeaker -> "Phone Speaker"
								isHeadphones -> "Wired Headphones"
								d.type == AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Audio"
								d.type == AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing Aid"
								d.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone Earpiece"
								else -> "Audio Output"
							}

							val rawName = d.productName?.toString()?.trim() ?: ""
							val name = if (rawName.isNotEmpty()) {
								rawName
							} else {
								typeLabel
							}

							val isCurrent = if (currentCommDevice != null) {
								currentCommDevice.id == d.id
							} else if (isSpeaker && am.isSpeakerphoneOn) {
								true
							} else {
								false
							}

							resultList.add(
								mapOf(
									"id" to d.id,
									"name" to name,
									"type" to d.type,
									"typeLabel" to typeLabel,
									"isBluetooth" to isBt,
									"isSpeaker" to isSpeaker,
									"isHeadphones" to isHeadphones,
									"isCurrent" to isCurrent
								)
							)
						}
					}
					result.success(resultList)
				}
				"openMediaOutputSwitcher" -> {
					var opened = false
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
						try {
							val intent = Intent("com.android.settings.panel.action.MEDIA_OUTPUT").apply {
								putExtra("com.android.settings.panel.extra.PACKAGE_NAME", packageName)
								addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							}
							startActivity(intent)
							opened = true
						} catch (_: Exception) {}
					}
					if (!opened) {
						try {
							val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
								addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							}
							startActivity(intent)
							opened = true
						} catch (_: Exception) {}
					}
					result.success(opened)
				}
				"setAudioDevice" -> {
					val deviceId = call.argument<Int>("deviceId")
					val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
					if (deviceId == null || deviceId == -1) {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
							try { am.clearCommunicationDevice() } catch (_: Exception) {}
						}
						am.isSpeakerphoneOn = false
						result.success(true)
					} else {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
							val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
							val target = devices.find { it.id == deviceId }
							if (target != null) {
								var routed = false
								if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
									try {
										routed = am.setCommunicationDevice(target)
									} catch (_: Exception) {}
								}
								if (!routed) {
									if (target.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
										am.isSpeakerphoneOn = true
									} else {
										am.isSpeakerphoneOn = false
									}
								}
								result.success(true)
							} else {
								result.success(false)
							}
						} else {
							result.success(false)
						}
					}
				}
				else -> result.notImplemented()
			}
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"updateMediaStoreTags" -> {
					val path = call.argument<String>("path")
					if (path == null) {
						result.error("bad_args", "path is required", null)
						return@setMethodCallHandler
					}
					try {
						val title = call.argument<String>("title")
						val artist = call.argument<String>("artist")
						val album = call.argument<String>("album")
						val year = call.argument<Int>("year")
						val track = call.argument<Int>("track")
						val genre = call.argument<String>("genre")
						val composer = call.argument<String>("composer")

						val values = ContentValues().apply {
							if (title != null) put(MediaStore.Audio.Media.TITLE, title)
							if (artist != null) put(MediaStore.Audio.Media.ARTIST, artist)
							if (album != null) put(MediaStore.Audio.Media.ALBUM, album)
							if (year != null && year > 0) put(MediaStore.Audio.Media.YEAR, year)
							if (track != null && track > 0) put(MediaStore.Audio.Media.TRACK, track)
							if (composer != null) put(MediaStore.Audio.Media.COMPOSER, composer)
							if (genre != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
								put(MediaStore.Audio.Media.GENRE, genre)
							}
							put(MediaStore.Audio.Media.DATE_MODIFIED, System.currentTimeMillis() / 1000)
						}

						val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
						val count = contentResolver.update(
							uri,
							values,
							"${MediaStore.Audio.Media.DATA} = ?",
							arrayOf(path)
						)

						// Also trigger MediaScannerConnection to update thumbnails and system caches,
						// and reinforce values in the scan callback to prevent scanner overwrites.
						MediaScannerConnection.scanFile(this, arrayOf(path), null) { scannedPath, scannedUri ->
							try {
								val postScanValues = ContentValues().apply {
									if (year != null && year > 0) put(MediaStore.Audio.Media.YEAR, year)
									if (title != null) put(MediaStore.Audio.Media.TITLE, title)
									if (artist != null) put(MediaStore.Audio.Media.ARTIST, artist)
									if (album != null) put(MediaStore.Audio.Media.ALBUM, album)
									if (track != null && track > 0) put(MediaStore.Audio.Media.TRACK, track)
									if (composer != null) put(MediaStore.Audio.Media.COMPOSER, composer)
									if (genre != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
										put(MediaStore.Audio.Media.GENRE, genre)
									}
								}
								if (postScanValues.size() > 0) {
									if (scannedUri != null) {
										contentResolver.update(scannedUri, postScanValues, null, null)
									} else {
										contentResolver.update(
											MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
											postScanValues,
											"${MediaStore.Audio.Media.DATA} = ?",
											arrayOf(path)
										)
									}
								}
							} catch (_: Exception) {}
						}

						result.success(count > 0)
					} catch (e: Exception) {
						try {
							MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, _ -> }
						} catch (_: Exception) {}
						result.success(false)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
}
