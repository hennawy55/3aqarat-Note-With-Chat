import { App } from '@capacitor/app';

App.addListener('backButton', () => {
  // A native chat screen owns the first Back press and returns to its room list.
  try {
    if (typeof window.smartNoteChatBack === 'function' && window.smartNoteChatBack()) return;
  } catch (error) {
    console.warn('Could not close the active chat screen:', error);
  }
  window.dispatchEvent(new CustomEvent('smartnote-back-button'));
});
