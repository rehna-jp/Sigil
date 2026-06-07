import WebSocket from 'ws';

export function startKeeper(wsUrl: string) {
  const ws = new WebSocket(wsUrl);
  ws.on('open', () => console.log('Keeper connected to', wsUrl));
  ws.on('message', (data) => console.log('Keeper msg:', data.toString()));
  ws.on('close', () => console.log('Keeper disconnected'));
  return ws;
}
