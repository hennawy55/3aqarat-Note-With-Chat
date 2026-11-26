import { App } from '@capacitor/app';

App.addListener('backButton', () => {
  // Give the open chat first priority so Android's system Back returns
  // to the conversation list instead of navigating away from the page.
  if (typeof window.smartNoteChatBack === 'function' && window.smartNoteChatBack()) return;
  window.dispatchEvent(new CustomEvent('smartnote-back-button'));
});
