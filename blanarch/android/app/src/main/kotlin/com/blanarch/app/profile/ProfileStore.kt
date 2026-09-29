package com.blanarch.app.profile

import android.content.Context
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray

/** Persistence for profiles. An interface so the engine and bridge can be tested without Android. */
interface ProfileStore {
    val profiles: StateFlow<List<Profile>>
    fun get(id: String): Profile?
    fun save(profile: Profile): Profile
    fun delete(id: String)

    companion object {
        fun newId(): String = UUID.randomUUID().toString()
    }
}

/** Profiles as a JSON array in private SharedPreferences. */
class PrefsProfileStore(context: Context) : ProfileStore {
    private val prefs = context.getSharedPreferences("profiles", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(load())
    override val profiles: StateFlow<List<Profile>> = state.asStateFlow()

    private fun load(): List<Profile> = runCatching {
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        (0 until arr.length()).map { Profile.fromJson(arr.getJSONObject(it)) }
    }.getOrDefault(emptyList())

    private fun persist(list: List<Profile>) {
        prefs.edit().putString(KEY, JSONArray(list.map { it.toJson() }).toString()).apply()
        state.value = list
    }

    override fun get(id: String): Profile? = state.value.firstOrNull { it.id == id }

    @Synchronized
    override fun save(profile: Profile): Profile {
        val list = state.value.toMutableList()
        val i = list.indexOfFirst { it.id == profile.id }
        if (i >= 0) list[i] = profile else list += profile
        persist(list)
        return profile
    }

    @Synchronized
    override fun delete(id: String) = persist(state.value.filterNot { it.id == id })

    private companion object {
        const val KEY = "profiles"
    }
}
