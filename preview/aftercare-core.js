// A session-local invitation policy. It has no storage, timers, audio, HealthKit,
// outfit changes, or animation side effects: the caller owns explicit playback.
export const AFTERCARE_VARIANTS = Object.freeze(['towel', 'drink', 'rest']);
const EXERCISE = new Set(['exercise', 'walking', 'running', 'strength']);
const validID = id => typeof id === 'string' && id.trim() === id && id.length > 0 && id.length <= 128;
const validTime = value => Number.isFinite(value) && value >= 0;
const canonicalVariants = value => AFTERCARE_VARIANTS.filter(id => Array.isArray(value) && value.includes(id));
const sameEvent = (a, b) => a.id === b.id && a.kind === b.kind && a.status === b.status && a.endedAtMS === b.endedAtMS;

export class AftercarePolicy {
  #state = { phase: 'idle', reason: 'waiting', eventID: null, kind: null, variant: null,
    mode: 'live', availableVariants: [], offeredAtMS: null, playingAtMS: null };
  #allowed = false;
  #observed = null;
  #seen = new Map();
  #observedKinds = new Map();
  #blocked = new Set();
  #now = null;
  #review = 0;
  #endedAtMS = null;
  get state() { return { ...this.#state, availableVariants: [...this.#state.availableVariants] }; }
  #time(nowMS) {
    if (!validTime(nowMS)) { this.#cancel('invalidTime'); return false; }
    if (this.#now !== null && nowMS < this.#now) { this.#now = nowMS; this.#cancel('clockChanged'); return false; }
    this.#now = nowMS; return true;
  }
  #cancel(reason) {
    this.#observed = null;
    if (['offered', 'playing'].includes(this.#state.phase)) this.#state.phase = 'dismissed';
    this.#state.reason = reason;
    return this.state;
  }
  #reject(reason) { this.#state.reason = reason; return this.state; }
  updateVisibility({ active, lowPower = false, reduceMotion = false, nowMS } = {}) {
    if (!this.#time(nowMS)) { this.#allowed = false; return this.state; }
    const allowed = active === true && lowPower === false && reduceMotion === false;
    if (!allowed) this.#cancel(active !== true ? 'inactive' : lowPower !== false ? 'lowPower' : 'reduceMotion');
    this.#allowed = allowed;
    return this.state;
  }
  observeActivity({ id, kind, status, nowMS } = {}) {
    if (!this.#time(nowMS)) return this.state;
    if (!this.#allowed) return this.#cancel('inactive');
    if (!validID(id) || !['exercise', 'walking', 'running', 'strength', 'focus', 'breathing'].includes(kind)) return this.#cancel('invalidActivity');
    if (status !== 'running') return this.#cancel(status === 'paused' ? 'activityPaused' : 'invalidActivity');
    if (this.#seen.has(id)) return this.#cancel('reusedActivity');
    if (this.#blocked.has(id) || (this.#observedKinds.has(id) && this.#observedKinds.get(id) !== kind)) {
      this.#blocked.add(id); return this.#cancel('conflictingActivity');
    }
    this.#observedKinds.set(id, kind);
    if (this.#observed?.id !== id || (['offered', 'playing'].includes(this.#state.phase) && this.#state.eventID !== id)) this.#cancel('newActivity');
    if (!this.#observed) this.#observed = { id, kind, observedAtMS: nowMS };
    return this.state;
  }
  receiveCompletion(event, { nowMS, availableVariants = [] } = {}) {
    if (!this.#time(nowMS)) return this.state;
    if (!event || !validID(event.id)) return this.#reject('invalidEvent');
    const original = this.#seen.get(event.id);
    if (original) {
      if (sameEvent(original, event)) return this.state;
      if (this.#state.eventID === event.id) this.#cancel('conflictingEvent');
      return this.#reject('conflictingEvent');
    }
    // Consume every identified completion, even while hidden or when malformed.
    // Showing the screen again cannot replay a cached event.
    this.#seen.set(event.id, { id: event.id, kind: event.kind, status: event.status, endedAtMS: event.endedAtMS });
    if (this.#blocked.has(event.id)) return this.#reject('conflictingActivity');
    if (event.status !== 'completed') {
      if (this.#observed?.id === event.id) this.#observed = null;
      return this.#reject(event.status === 'cancelled' ? 'cancelled' : 'invalidEvent');
    }
    if (!EXERCISE.has(event.kind)) return this.#reject('notExercise');
    if (!validTime(event.endedAtMS)) return this.#reject('invalidEvent');
    if (event.endedAtMS > nowMS) return this.#reject('futureEvent');
    if (nowMS - event.endedAtMS > 60_000) return this.#reject('staleEvent');
    if (!this.#allowed) return this.#reject('inactive');
    if (this.#observed?.id !== event.id || this.#observed.kind !== event.kind || event.endedAtMS < this.#observed.observedAtMS) return this.#reject('notObserved');
    this.#observed = null;
    const available = canonicalVariants(availableVariants);
    if (!available.length) return this.#reject('noAssets');
    this.#endedAtMS = event.endedAtMS;
    this.#state = { phase: 'offered', reason: 'completionObserved', eventID: event.id, kind: event.kind,
      variant: null, mode: 'live', availableVariants: available, offeredAtMS: nowMS, playingAtMS: null };
    return this.state;
  }
  beginReview({ kind = 'exercise', nowMS, availableVariants = [] } = {}) {
    if (!this.#time(nowMS)) return this.state;
    if (!this.#allowed) return this.#reject('inactive');
    if (!EXERCISE.has(kind)) return this.#reject('notExercise');
    const available = canonicalVariants(availableVariants);
    if (!available.length) return this.#reject('noAssets');
    this.#observed = null; this.#endedAtMS = nowMS;
    this.#state = { phase: 'offered', reason: 'manualReview', eventID: `review-${++this.#review}`,
      kind, variant: null, mode: 'review', availableVariants: available, offeredAtMS: nowMS, playingAtMS: null };
    return this.state;
  }
  choose(variant, nowMS) {
    this.tick(nowMS);
    if (this.#state.phase !== 'offered') return this.state;
    if (!this.#allowed) return this.#cancel('inactive');
    if (!this.#state.availableVariants.includes(variant)) return this.#reject('unavailableVariant');
    this.#state.phase = 'playing'; this.#state.variant = variant;
    this.#state.playingAtMS = nowMS; this.#state.reason = 'userChoice';
    return this.state;
  }
  finish(nowMS) {
    this.tick(nowMS);
    if (this.#state.phase === 'playing') { this.#state.phase = 'done'; this.#state.reason = 'finished'; }
    return this.state;
  }
  dismiss() { return this.#cancel('userDismissed'); }
  tick(nowMS) {
    if (!this.#time(nowMS)) return this.state;
    if (this.#state.phase === 'offered' && nowMS - this.#endedAtMS > 60_000) return this.#cancel('offerExpired');
    if (this.#state.phase === 'playing' && nowMS - this.#state.playingAtMS > 20_000) return this.#cancel('playbackTimeout');
    return this.state;
  }
}
