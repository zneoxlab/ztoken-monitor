'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { stripSessionDetailFromRecord } = require('../src/deviceRecord');

test('stripSessionDetailFromRecord removes sessions from every period', () => {
  const stripped = stripSessionDetailFromRecord({
    deviceId: 'dev-a',
    sessionDetailsOmitted: { month: 12 },
    periods: {
      today: { totalTokens: 1, sessions: { a: { totalTokens: 1 } } },
      month: { totalTokens: 2, sessions: { b: { totalTokens: 2 } } },
      allTime: { totalTokens: 3, sessions: { c: { totalTokens: 3 } } }
    }
  });

  assert.equal(Object.hasOwn(stripped, 'sessionDetailsOmitted'), false);
  assert.equal(Object.hasOwn(stripped.periods.today, 'sessions'), false);
  assert.equal(Object.hasOwn(stripped.periods.month, 'sessions'), false);
  assert.equal(Object.hasOwn(stripped.periods.allTime, 'sessions'), false);
  assert.equal(stripped.periods.today.totalTokens, 1);
  assert.equal(stripped.periods.month.totalTokens, 2);
  assert.equal(stripped.periods.allTime.totalTokens, 3);
});

test('stripSessionDetailFromRecord tolerates flat period fields', () => {
  const stripped = stripSessionDetailFromRecord({
    today: { totalTokens: 4, sessions: { x: { totalTokens: 4 } } }
  });
  assert.equal(stripped.today.totalTokens, 4);
  assert.equal(Object.hasOwn(stripped.today, 'sessions'), false);
});
