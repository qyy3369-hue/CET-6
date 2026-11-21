const controls = 'button, .sidebar a, .sidebar summary, .toolbar a, #content a.chip';
const interactions = new WeakMap();

function controlAt(target) {
  return target instanceof Element ? target.closest(controls) : null;
}

function usable(control) {
  return control && !control.matches(':disabled,[aria-disabled="true"]');
}

function makeReveal(control, x, y) {
  const rectangle = control.getBoundingClientRect();
  const left = Math.min(rectangle.width, Math.max(0, x - rectangle.left));
  const top = Math.min(rectangle.height, Math.max(0, y - rectangle.top));
  const radius = Math.hypot(Math.max(left, rectangle.width - left), Math.max(top, rectangle.height - top)) + 2;
  const style = getComputedStyle(control);
  const reveal = document.createElement('span');
  reveal.className = 'goals-button-reveal';
  reveal.setAttribute('aria-hidden','true');
  reveal.inert = true;
  for (const property of ['display','padding','alignItems','justifyContent','flexDirection','flexWrap','gap','textAlign']) {
    reveal.style[property] = style[property];
  }
  reveal.style.setProperty('--fill-x', left + 'px');
  reveal.style.setProperty('--fill-y', top + 'px');
  reveal.style.setProperty('--fill-radius', radius + 'px');
  for (const child of control.childNodes) {
    if (child instanceof Element && child.classList.contains('goals-button-reveal')) continue;
    const copy = child.cloneNode(true);
    if (copy instanceof Element) {
      copy.removeAttribute('id');
      copy.querySelectorAll('[id]').forEach(element => element.removeAttribute('id'));
    }
    reveal.append(copy);
  }
  if (control.localName === 'summary') {
    const chevron = document.createElement('span');
    chevron.className = 'goals-reveal-chevron';
    chevron.textContent = '›';
    reveal.append(chevron);
  }
  return reveal;
}

function show(control, event, source) {
  if (!usable(control)) return;
  let state = interactions.get(control);
  if (state) {
    state[source] = true;
    if (state.visible) return;
    state.layer.classList.remove('is-revealed');
    state.layer.remove();
  }
  const rectangle = control.getBoundingClientRect();
  const x = event?.clientX ?? rectangle.left + rectangle.width / 2;
  const y = event?.clientY ?? rectangle.top + rectangle.height / 2;
  const layer = makeReveal(control,x,y);
  state = { layer, visible:true, pointer:false, pressed:false, ...state, [source]:true };
  state.layer = layer;
  state.visible = true;
  interactions.set(control,state);
  control.classList.add('goals-motion-control');
  control.append(layer);
  // Establish the collapsed clip before starting the transition from the entry point.
  getComputedStyle(layer).clipPath;
  layer.classList.add('is-revealed');
}

function hide(control, source) {
  const state = interactions.get(control);
  if (!state) return;
  state[source] = false;
  if (state.pointer || state.pressed || !state.visible) return;
  state.visible = false;
  state.layer.classList.remove('is-revealed');
  const layer = state.layer;
  setTimeout(() => {
    const current = interactions.get(control);
    if (current?.visible || current?.layer !== layer) return;
    layer.remove();
    interactions.delete(control);
  }, 520);
}

export function installButtonMotion() {
  document.addEventListener('pointerover', event => {
    if (event.pointerType !== 'mouse' && event.pointerType !== 'pen') return;
    const control = controlAt(event.target);
    if (!usable(control) || (event.relatedTarget instanceof Node && control.contains(event.relatedTarget))) return;
    show(control,event,'pointer');
  });
  document.addEventListener('pointerout', event => {
    const control = controlAt(event.target);
    if (!control || (event.relatedTarget instanceof Node && control.contains(event.relatedTarget))) return;
    hide(control,'pointer');
  });
  let pressedControl = null;
  document.addEventListener('pointerdown', event => {
    const control = controlAt(event.target);
    if (event.button !== 0 || !usable(control)) return;
    pressedControl = control;
    show(control,event,'pressed');
  });
  const releasePointer = () => {
    if (pressedControl) hide(pressedControl,'pressed');
    pressedControl = null;
  };
  document.addEventListener('pointerup',releasePointer);
  document.addEventListener('pointercancel',releasePointer);
  const activationKey = event => event.key === 'Enter' || event.key === ' ';
  document.addEventListener('keydown', event => {
    if (activationKey(event) && !event.repeat) show(controlAt(event.target),null,'pressed');
  });
  document.addEventListener('keyup', event => {
    if (activationKey(event)) hide(controlAt(event.target),'pressed');
  });
  document.addEventListener('focusout', event => hide(controlAt(event.target),'pressed'));
}
