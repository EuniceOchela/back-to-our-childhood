import {
  signUp, signIn, signOut, sendPasswordReset, getCurrentUser,
  onAuthChange, getProfile, updateProfile
} from "./auth.js";
import {
  createRoom, joinRoom, setReady, startRoom, leaveRoom,
  getRoom, getRoomPlayers, shareRoom, GAME_LABELS
} from "./rooms.js";
import { subscribeToRoom } from "./realtime.js";
import { getMyStats, getLeaderboard, createMemory, getPublishedMemories } from "./profile.js";

const $ = id => document.getElementById(id);
const modal = $("bocBackendModal");
const body = $("bocBackendBody");
const title = $("bocBackendModalTitle");
const subtitle = $("bocBackendModalSubtitle");
let currentUser = null;
let currentRoom = null;
let stopRealtime = null;
let heartbeatTimer = null;

function configured() {
  return Boolean(window.BOC_SUPABASE_READY);
}

function showModal(t, s, html) {
  title.textContent = t;
  subtitle.textContent = s;
  body.innerHTML = html;
  modal.style.display = "flex";
}

function closeModal() {
  modal.style.display = "none";
}

function setStatus(message) {
  $("backendStatus").textContent = message;
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, c => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"
  }[c]));
}

function authForm(mode = "signin") {
  const signup = mode === "signup";
  showModal(
    signup ? "Create your player account" : "Welcome back",
    signup ? "Choose your own identity and avatar." : "Sign in to create or join online rooms.",
    `<form id="bocAuthForm" style="display:grid;gap:10px">
      ${signup ? `<input class="field" id="bocDisplayName" placeholder="Display name" maxlength="40" required>
      <input class="field" id="bocUsername" placeholder="Username (optional)" maxlength="24">
      <select class="field" id="bocAvatar">
        <option>🧒🏾</option><option>👧🏿</option><option>🧒🏽</option><option>👧🏾</option><option>🧒🏿</option><option>👦🏾</option>
      </select>` : ""}
      <input class="field" id="bocEmail" type="email" placeholder="Email" autocomplete="email" required>
      <input class="field" id="bocPassword" type="password" placeholder="Password" minlength="6" autocomplete="${signup ? "new-password" : "current-password"}" required>
      <button class="btn btn-primary" type="submit">${signup ? "Create account" : "Sign in"}</button>
      <button class="btn btn-outline" type="button" id="bocForgot">${signup ? "Already have an account? Sign in" : "Forgot password?"}</button>
      <button class="btn btn-outline" type="button" id="bocSwitch">${signup ? "I already have an account" : "Create a new account"}</button>
    </form>`
  );

  $("bocAuthForm").onsubmit = async e => {
    e.preventDefault();
    try {
      if (signup) {
        const result = await signUp({
          email: $("bocEmail").value,
          password: $("bocPassword").value,
          displayName: $("bocDisplayName").value,
          username: $("bocUsername").value,
          avatar: $("bocAvatar").value
        });
        if (result.session) {
          currentUser = result.user;
          closeModal();
        } else {
          showModal("Check your email", "Your account was created. Confirm your email, then sign in.", `<button class="btn btn-primary" id="bocBackSignIn">Sign in</button>`);
          $("bocBackSignIn").onclick = () => authForm("signin");
        }
      } else {
        await signIn($("bocEmail").value, $("bocPassword").value);
        closeModal();
      }
    } catch (err) {
      alert(err.message);
    }
  };

  $("bocSwitch").onclick = () => authForm(signup ? "signin" : "signup");
  $("bocForgot").onclick = () => {
    showModal("Reset your password", "We'll send a recovery email.", `<form id="bocReset" style="display:grid;gap:10px">
      <input class="field" id="bocResetEmail" type="email" placeholder="Email" required>
      <button class="btn btn-primary">Send reset email</button>
    </form>`);
    $("bocReset").onsubmit = async e => {
      e.preventDefault();
      try { await sendPasswordReset($("bocResetEmail").value); alert("Password reset email sent."); closeModal(); }
      catch (err) { alert(err.message); }
    };
  };
}

async function accountPanel() {
  if (!currentUser) return authForm("signin");
  const profile = await getProfile(currentUser.id);
  const stats = await getMyStats();
  showModal("Your player profile", "Your online identity belongs to you — not to a fictional story character.", `
    <form id="bocProfileForm" style="display:grid;gap:10px">
      <input class="field" id="bocProfileName" value="${escapeHtml(profile.display_name)}" maxlength="40" required>
      <input class="field" id="bocProfileUsername" value="${escapeHtml(profile.username || "")}" maxlength="24" placeholder="Username">
      <select class="field" id="bocProfileAvatar">${["🧒🏾","👧🏿","🧒🏽","👧🏾","🧒🏿","👦🏾"].map(a=>`<option ${a===profile.avatar?"selected":""}>${a}</option>`).join("")}</select>
      <p>Games played: ${stats?.games_played ?? 0} · Wins: ${stats?.wins ?? 0} · Total score: ${stats?.total_score ?? 0}</p>
      <button class="btn btn-primary">Save profile</button>
      <button class="btn btn-outline" type="button" id="bocLogout">Log out</button>
    </form>`);
  $("bocProfileForm").onsubmit = async e => {
    e.preventDefault();
    try {
      const updated = await updateProfile(currentUser.id, {
        display_name: $("bocProfileName").value,
        username: $("bocProfileUsername").value,
        avatar: $("bocProfileAvatar").value
      });
      $("navPlayer").textContent = updated.display_name;
      closeModal();
    } catch (err) { alert(err.message); }
  };
  $("bocLogout").onclick = async () => { await signOut(); closeModal(); };
}

async function roomPanel() {
  if (!currentUser) return authForm("signin");
  showModal("Create an online room", "Choose one of the launch multiplayer games.", `
    <form id="bocRoomForm" style="display:grid;gap:10px">
      <select class="field" id="bocGame">
        <option value="ten_ten">Ten-Ten</option>
        <option value="name_animal_place_and_thing">Name, Animal, Place and Thing</option>
        <option value="ayo">Ayo</option>
      </select>
      <select class="field" id="bocMax"><option>2</option><option>3</option><option>4</option><option>5</option><option>6</option><option>7</option><option>8</option></select>
      <label><input type="checkbox" id="bocPrivate"> Private room</label>
      <button class="btn btn-primary">Create room</button>
    </form>
    <hr>
    <form id="bocJoinForm" style="display:grid;gap:10px">
      <input class="field" id="bocCode" placeholder="Enter 6-character room code" maxlength="6" required>
      <button class="btn btn-outline">Join room</button>
    </form>`);

  $("bocRoomForm").onsubmit = async e => {
    e.preventDefault();
    try {
      const room = await createRoom($("bocGame").value, Number($("bocMax").value), $("bocPrivate").checked);
      currentRoom = room;
      await renderLobby(room.id);
    } catch (err) { alert(err.message); }
  };

  $("bocJoinForm").onsubmit = async e => {
    e.preventDefault();
    try {
      const member = await joinRoom($("bocCode").value);
      currentRoom = await getRoom(member.room_id);
      await renderLobby(member.room_id);
    } catch (err) { alert(err.message); }
  };
}

async function renderLobby(roomId) {
  currentRoom = await getRoom(roomId);
  const players = await getRoomPlayers(roomId);
  const isHost = currentRoom.host_id === currentUser.id;
  const active = players.length;
  showModal(`${GAME_LABELS[currentRoom.game_type]} · Room ${currentRoom.room_code}`, "Real-time lobby — changes are synchronized through Supabase.", `
    <div id="bocLobby">
      <p><strong>${active}/${currentRoom.max_players} players</strong> · ${escapeHtml(currentRoom.status)}</p>
      <div style="display:grid;gap:8px">${players.map(p => `
        <div style="padding:10px;border:1px solid rgba(0,0,0,.12);border-radius:12px;display:flex;justify-content:space-between;gap:10px">
          <span>${escapeHtml(p.profiles?.avatar || "🧒🏾")} ${escapeHtml(p.profiles?.display_name || "Player")} ${p.is_host ? "— HOST" : ""}</span>
          <span>${p.is_ready ? "READY" : "NOT READY"}</span>
        </div>`).join("")}</div>
      <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px">
        <button class="btn btn-primary btn-small" id="bocReady">Ready / Not ready</button>
        <button class="btn btn-outline btn-small" id="bocCopy">Copy room code</button>
        <button class="btn btn-outline btn-small" id="bocShare">Invite friends</button>
        ${isHost ? `<button class="btn btn-secondary btn-small" id="bocStart">Start game</button>` : ""}
        <button class="btn btn-outline btn-small" id="bocLeave">Leave</button>
      </div>
    </div>`);

  const me = players.find(p => p.user_id === currentUser.id);
  $("bocReady").onclick = async () => {
    try { await setReady(roomId, !me?.is_ready); } catch (err) { alert(err.message); }
  };
  $("bocCopy").onclick = async () => {
    await navigator.clipboard.writeText(currentRoom.room_code);
    alert("Room code copied.");
  };
  $("bocShare").onclick = () => shareRoom(currentRoom.room_code, GAME_LABELS[currentRoom.game_type]);
  $("bocLeave").onclick = async () => {
    try { await leaveRoom(roomId); cleanupRoom(); closeModal(); } catch (err) { alert(err.message); }
  };
  if ($("bocStart")) $("bocStart").onclick = async () => {
    try { await startRoom(roomId); } catch (err) { alert(err.message); }
  };

  if (stopRealtime) stopRealtime();
  stopRealtime = subscribeToRoom(roomId, {
    room: async () => renderLobby(roomId),
    players: async () => renderLobby(roomId),
    session: payload => {
      if (payload.new) setStatus(`Online game session is active: ${GAME_LABELS[payload.new.game_type]}.`);
    }
  });

  if (heartbeatTimer) clearInterval(heartbeatTimer);
  heartbeatTimer = setInterval(async () => {
    try {
      const { heartbeat } = await import("./rooms.js");
      await heartbeat(roomId);
    } catch {}
  }, 15000);
}

function cleanupRoom() {
  if (stopRealtime) stopRealtime();
  stopRealtime = null;
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  heartbeatTimer = null;
  currentRoom = null;
}

async function init() {
  $("bocBackendClose").onclick = closeModal;
  $("bocSignInButton").onclick = () => authForm(currentUser ? "signin" : "signin");
  $("bocRoomButton").onclick = roomPanel;
  $("bocAccountButton").onclick = accountPanel;

  if (!configured()) {
    setStatus("Supabase is not configured yet. The original local website remains usable. Add your project URL and publishable key to enable accounts and real online rooms.");
    return;
  }

  const user = await getCurrentUser();
  currentUser = user;
  updateHeader();

  onAuthChange(async (_event, session) => {
    currentUser = session?.user || null;
    updateHeader();
  });

  const hash = new URLSearchParams(window.location.hash.replace("#", "?"));
  const joinCode = hash.get("join");
  if (joinCode && currentUser) {
    try {
      const member = await joinRoom(joinCode);
      await renderLobby(member.room_id);
    } catch (err) {
      setStatus(`Invite link could not be joined: ${err.message}`);
    }
  }
}

async function updateHeader() {
  if (!currentUser) {
    $("navPlayer").textContent = "Sign in";
    $("bocSignInButton").textContent = "Sign in";
    setStatus("Guests can browse the childhood games. Sign in to create or join real online rooms.");
    return;
  }
  try {
    const profile = await getProfile(currentUser.id);
    $("navPlayer").textContent = profile.display_name;
    $("bocSignInButton").textContent = "My profile";
    setStatus(`Signed in as ${profile.display_name}. You can now create or join a real online room.`);
  } catch {}
}

init().catch(err => setStatus(`Backend connection error: ${err.message}`));
