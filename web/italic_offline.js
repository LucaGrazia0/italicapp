// Only same-origin application resources are cached. Observations stay in IndexedDB.
(() => {
  let progress = null;
  const worker = async () => {
    if (!('serviceWorker' in navigator) || !window.isSecureContext) {
      throw new Error('Usa localhost oppure un indirizzo HTTPS.');
    }
    const registration = await navigator.serviceWorker.register('italic_offline_worker.js');
    await navigator.serviceWorker.ready;
    return registration.active;
  };
  async function request(action) {
    const target = await worker();
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      let timeout;
      const keepAlive = () => {
        clearTimeout(timeout);
        timeout = setTimeout(() => {
          channel.port1.close();
          reject(new Error('Operazione non completata. Riprova.'));
        }, 180000);
      };
      keepAlive();
      channel.port1.onmessage = ({data}) => {
        if (data.progress != null) { progress = data; keepAlive(); return; }
        clearTimeout(timeout);
        channel.port1.close();
        if (data.error) reject(new Error(data.error));
        else resolve(data);
      };
      target.postMessage({action}, [channel.port2]);
    });
  }
  window.italicOfflineStatus = async () => {
    try { return JSON.stringify(await request('status')); }
    catch (e) { return JSON.stringify({error: e.message}); }
  };
  window.italicOfflinePrepare = async () => {
    progress = {progress: 0};
    try {
      const result = await request('prepare');
      if (navigator.storage?.persist) await navigator.storage.persist().catch(() => false);
      return JSON.stringify(result);
    } catch (e) { return JSON.stringify({error: e.message}); }
    finally { progress = null; }
  };
  window.italicOfflineProgress = () => JSON.stringify(progress || {});
})();
