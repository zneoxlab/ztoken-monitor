'use strict';

// SaaS hub wire/storage shape: session-level detail is not stored or broadcast.
// Mobile app does not consume it; desktop SaaS mode rebuilds session views locally.
// Self-hosted client/host hubs keep the full record unchanged.

const PERIOD_NAMES = ['today', 'month', 'allTime'];

function stripPeriodSessions(period) {
  if (!period || typeof period !== 'object') return period;
  if (!Object.prototype.hasOwnProperty.call(period, 'sessions')) return period;
  const next = { ...period };
  delete next.sessions;
  return next;
}

function stripSessionDetailFromRecord(record) {
  if (!record || typeof record !== 'object') return record;
  const next = { ...record };
  delete next.sessionDetailsOmitted;

  if (next.periods && typeof next.periods === 'object') {
    const periods = { ...next.periods };
    for (const periodName of PERIOD_NAMES) {
      if (periods[periodName]) periods[periodName] = stripPeriodSessions(periods[periodName]);
    }
    next.periods = periods;
  }

  for (const periodName of PERIOD_NAMES) {
    if (next[periodName]) next[periodName] = stripPeriodSessions(next[periodName]);
  }

  return next;
}

function stripSessionsFromStats(stats) {
  if (!stats || typeof stats !== 'object') return stats;
  const next = { ...stats };
  delete next.sessionDetailsOmitted;

  if (next.periods && typeof next.periods === 'object') {
    const periods = { ...next.periods };
    for (const periodName of PERIOD_NAMES) {
      if (periods[periodName]) periods[periodName] = stripPeriodSessions(periods[periodName]);
    }
    next.periods = periods;
  }

  if (Array.isArray(next.devices)) {
    next.devices = next.devices.map((device) => {
      if (!device?.periods || typeof device.periods !== 'object') return device;
      const periods = { ...device.periods };
      for (const periodName of PERIOD_NAMES) {
        if (periods[periodName]) periods[periodName] = stripPeriodSessions(periods[periodName]);
      }
      return { ...device, periods };
    });
  }

  return next;
}

module.exports = {
  PERIOD_NAMES,
  stripPeriodSessions,
  stripSessionDetailFromRecord,
  stripSessionsFromStats
};
