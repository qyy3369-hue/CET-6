const paths = {
  plus:'M12 5v14M5 12h14',
  scan:'M8 4H5a1 1 0 0 0-1 1v3m12-4h3a1 1 0 0 1 1 1v3M4 16v3a1 1 0 0 0 1 1h3m8 0h3a1 1 0 0 0 1-1v-3M8 9h8m-8 3h8m-8 3h5',
  chevron:'m6 9 6 6 6-6',
  'bookmark-fill':'M6 3h12v18l-6-4-6 4z',
  sparkles:'M12 2l2.4 6.6L21 11l-6.6 2.4L12 20l-2.4-6.6L3 11l6.6-2.4L12 2zm7 14v5m-2.5-2.5h5M5 2v4M3 4h4',
  folder:'M3 6a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  clipboard:'M9 5H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3M9 3h6v4H9z',
  photo:'M3 4h18v16H3zM8 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm-5 6 4-3 4 3 4-6 6 6',
  trash:'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 10v7m4-7v7',

  layout: 'M3 4h7v7H3zM14 4h7v7h-7zM3 15h7v5H3zM14 15h7v5h-7z',
  calendar: 'M5 4h14a2 2 0 0 1 2 2v13H3V6a2 2 0 0 1 2-2zM3 9h18M8 2v4m8-4v4M7 13h1m3 0h1m3 0h1m-9 3h1m3 0h1m3 0h1',
  users: 'M14 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-4M8 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm8-8a4 4 0 0 1 0 8',
  file: 'M5 3h9l5 5v13H5zM14 3v6h5M8 13h8m-8 4h6',
  book: 'M5 3h14v17H6a2 2 0 0 1-2-2V5a2 2 0 0 1 1-2zM7 3v13m12 0H7a3 3 0 0 0-3 2',
  books: 'M3 5h4v15H3zM9 3h4v17H9zM15 6l4-1 3 14-4 1z',
  cards: 'M5 4h14M3 7h18M4 10h16a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z',
  bookmark: 'M6 3h12v18l-6-4-6 4z',
  chat: 'M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-7l-5 4v-4H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm3 5h8m-8 4h5',
  translate: 'M3 6h11M8 3v3m4 0c0 5-4 9-8 11m1-8c2 4 4 5 7 7m1 4 4-10 4 10m-7-3h6',
  pen: 'M14 4h-8a3 3 0 0 0-3 3v12a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-7m-8 4-4 1 1-4L19 3l3 3z',
  network: 'M12 11a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm-7-7a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm14 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM12 19a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM7 8l3 3m7-3-3 3m-2 4v4',
  gear: 'M9 3h6l.6 3 2.8 1.6 2.7-1 2 3.5-2.2 2v3l2.2 2-2 3.5-2.7-1L15.6 21h-6l-.6-3-2.8-1.6-2.7 1-2-3.5 2.2-2v-3l-2.2-2 2-3.5 2.7 1L9 3zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z',
  sidebar: 'M3 5h18v14H3zM9 5v14M6 8h1m-1 4h1',
  search: 'M10 17a7 7 0 1 0 0-14 7 7 0 0 0 0 14zm5-2 6 6',
  speaker: 'M3 9v6h4l5 4V5L7 9zm12-1a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14',
  cut: 'M7 8a3 3 0 1 0-4 4 3 3 0 0 0 4-4zm0 8a3 3 0 1 0-4 4 3 3 0 0 0 4-4zm0-5L20 3M7 15l13 6',
};
export function addIcon(element, name) {
  const path = paths[name];
  if (!path) return element;
  const namespace = 'http://www.w3.org/2000/svg';
  const icon = document.createElementNS(namespace, 'svg');
  icon.setAttribute('aria-hidden', 'true');
  icon.setAttribute('viewBox', '0 0 24 24');
  icon.setAttribute('class','icon');
  const drawing = document.createElementNS(namespace, 'path');
  drawing.setAttribute('d',path);
  drawing.setAttribute('fill',name==='bookmark-fill' ? 'currentColor' : 'none');
  drawing.setAttribute('stroke','currentColor');
  drawing.setAttribute('stroke-width','1.6');
  drawing.setAttribute('stroke-linecap','round');
  drawing.setAttribute('stroke-linejoin','round');
  icon.append(drawing);
  element.prepend(icon);
  return element;
}
