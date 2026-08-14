'use strict';

const crypto = require('node:crypto');

// 只接受服务端注入的密钥材料。派生后的两个子密钥分别负责 AES-GCM 和令牌查重，
// 所以数据库中既没有明文 token，也不会把可比较的原 token 直接暴露出去。
function createPushTokenCrypto(secret, { keyVersion = 1 } = {}) {
  if (!secret || (Buffer.isBuffer(secret) && secret.length === 0)) return null;
  const material = Buffer.isBuffer(secret) ? secret : Buffer.from(String(secret), 'utf8');
  const root = crypto.createHash('sha256').update(material).digest();
  const encryptionKey = crypto.createHmac('sha256', root).update('push-token-encryption-v1').digest();
  const hashKey = crypto.createHmac('sha256', root).update('push-token-hash-v1').digest();

  function encrypt(token) {
    const value = String(token || '').trim();
    if (!value) {
      const error = new Error('push token is required');
      error.code = 'bad_push_installation';
      throw error;
    }
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey, iv);
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return {
      tokenHash: crypto.createHmac('sha256', hashKey).update(value, 'utf8').digest('hex'),
      tokenCiphertext: ciphertext.toString('base64'),
      tokenIv: iv.toString('base64'),
      tokenTag: cipher.getAuthTag().toString('base64'),
      keyVersion
    };
  }

  function decrypt(envelope) {
    const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey, Buffer.from(envelope.tokenIv, 'base64'));
    decipher.setAuthTag(Buffer.from(envelope.tokenTag, 'base64'));
    return Buffer.concat([
      decipher.update(Buffer.from(envelope.tokenCiphertext, 'base64')),
      decipher.final()
    ]).toString('utf8');
  }

  return { encrypt, decrypt, keyVersion };
}

module.exports = { createPushTokenCrypto };
