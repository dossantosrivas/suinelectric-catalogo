/* =====================================================================
   SUINBOT → CHAT DE LA TIENDA  (Cloudflare Pages Function: /api/telegram)
   ---------------------------------------------------------------------
   Telegram manda aquí cada mensaje que le escribes a SuinBot. Si es una
   RESPUESTA a un aviso "💬 Chat #12", el texto se guarda en Supabase y
   el visitante lo ve en la burbuja de chat de la tienda.

   Comandos:
     /chats      → últimos 10 chats de la tienda
     /ia 12      → vuelve a encender la IA en el chat 12 (/ia 12 off la apaga)

   Variables en Cloudflare (Workers & Pages → proyecto → Settings →
   Variables and Secrets, tipo "Secret", en Production):
     TELEGRAM_TOKEN           token de SuinBot
     TELEGRAM_CHAT_ID         tu chat_id (el mismo del Vault de Supabase)
     TELEGRAM_WEBHOOK_SECRET  una clave inventada por ti (letras y números)
     SUPABASE_URL             https://yqnlxhbjassrkudnhvpr.supabase.co
     SUPABASE_SECRET_KEY      clave secreta de Supabase (sb_secret_…)

   Conectar SuinBot a esta dirección (una sola vez, después de publicar):
     abre  https://suinelectric.com/api/telegram?configurar=TU_WEBHOOK_SECRET
   ===================================================================== */

const tg = (env, metodo, datos) =>
  fetch('https://api.telegram.org/bot' + env.TELEGRAM_TOKEN + '/' + metodo, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  }).then(r => r.json()).catch(e => ({ ok: false, description: String(e) }));

async function rpc(env, funcion, args){
  const clave = env.SUPABASE_SECRET_KEY || '';
  const headers = { 'Content-Type': 'application/json', apikey: clave };
  if (!clave.startsWith('sb_')) headers.Authorization = 'Bearer ' + clave; // claves antiguas (JWT)
  const url = (env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
  const r = await fetch(url + '/rest/v1/rpc/' + funcion, { method: 'POST', headers, body: JSON.stringify(args) });
  const texto = await r.text();
  if (!r.ok) throw new Error('Supabase ' + r.status + ': ' + texto.slice(0, 200));
  return JSON.parse(texto);
}

const esc = (t) => String(t == null ? '' : t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function hace(fecha){
  const min = Math.round((Date.now() - new Date(fecha).getTime()) / 60000);
  if (min < 1) return 'ahora';
  if (min < 60) return 'hace ' + min + ' min';
  const h = Math.round(min / 60);
  if (h < 24) return 'hace ' + h + ' h';
  return 'hace ' + Math.round(h / 24) + ' d';
}

// ---------- Configurar el webhook (GET /api/telegram?configurar=SECRETO) ----------
export async function onRequestGet({ request, env }){
  const u = new URL(request.url);
  const clave = u.searchParams.get('configurar');
  if (!clave) return new Response('SuinBot: chat de la tienda activo.', { status: 200 });
  if (!env.TELEGRAM_WEBHOOK_SECRET || clave !== env.TELEGRAM_WEBHOOK_SECRET){
    return new Response('Clave incorrecta.', { status: 403 });
  }
  const faltan = ['TELEGRAM_TOKEN', 'TELEGRAM_CHAT_ID', 'SUPABASE_SECRET_KEY'].filter(k => !env[k]);
  if (faltan.length) return new Response('Faltan variables en Cloudflare: ' + faltan.join(', '), { status: 500 });
  const res = await tg(env, 'setWebhook', {
    url: u.origin + '/api/telegram',
    secret_token: env.TELEGRAM_WEBHOOK_SECRET,
    allowed_updates: ['message'],
    drop_pending_updates: true,
  });
  if (res.ok){
    await tg(env, 'sendMessage', { chat_id: env.TELEGRAM_CHAT_ID, text: '✅ SuinBot conectado al chat de la tienda. Responde a los avisos "💬 Chat #…" para contestar a tus clientes. Escribe /chats para ver los últimos.' });
  }
  return new Response((res.ok ? '✅ Listo: SuinBot conectado a ' : '✗ Error: ') + (res.ok ? u.origin + '/api/telegram' : res.description),
    { status: res.ok ? 200 : 500, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}

// ---------- Mensajes que llegan desde Telegram ----------
export async function onRequestPost({ request, env }){
  const ok = new Response('ok');
  if (!env.TELEGRAM_WEBHOOK_SECRET ||
      request.headers.get('X-Telegram-Bot-Api-Secret-Token') !== env.TELEGRAM_WEBHOOK_SECRET){
    return new Response('no autorizado', { status: 401 });
  }
  let upd;
  try { upd = await request.json(); } catch (e) { return ok; }
  const msg = upd && upd.message;
  if (!msg || !msg.chat) return ok;
  // Solo tú (o tu grupo) puede responder a los clientes.
  if (String(msg.chat.id) !== String(env.TELEGRAM_CHAT_ID)) return ok;

  const decir = (texto) => tg(env, 'sendMessage', {
    chat_id: msg.chat.id, text: texto, parse_mode: 'HTML',
    reply_parameters: { message_id: msg.message_id, allow_sending_without_reply: true },
    disable_web_page_preview: true,
  });

  const texto = (msg.text || msg.caption || '').trim();

  try {
    // /chats → lista de los últimos chats
    if (/^\/chats\b/i.test(texto)){
      const lista = await rpc(env, 'chat_recientes', { p_limite: 10 });
      if (!lista.length) { await decir('Todavía no hay chats en la tienda.'); return ok; }
      await decir('<b>Últimos chats</b>\n\n' + lista.map(c =>
        '<b>#' + c.id + '</b> · ' + esc(c.nombre || 'Visitante') + (c.contacto ? ' · ' + esc(c.contacto) : '') +
        ' · ' + hace(c.ultimo) + '\n' + (c.ultimo_autor === 'cliente' ? '🟡 ' : c.ultimo_autor === 'asistente' ? '🤖 ' : '✓ ') + esc(c.ultimo_texto || '')
      ).join('\n\n') + '\n\n<i>Para escribirle a uno sin buscar su aviso: </i><code>#12 tu mensaje</code>');
      return ok;
    }
    // /ia 12  → vuelve a encender la IA en el chat 12   ·   /ia 12 off → la apaga
    const ia = texto.match(/^\/ia\s+#?(\d+)(?:\s+(on|off|si|sí|no))?\s*$/i);
    if (ia){
      const activa = !/^(off|no)$/i.test(ia[2] || '');
      const r = await rpc(env, 'chat_ia', { p_chat: Number(ia[1]), p_activa: activa });
      await decir(r && r.ok
        ? (activa ? '🤖 IA encendida en el chat #' : '🔕 IA apagada en el chat #') + ia[1] + (r.nombre ? ' (' + esc(r.nombre) + ')' : '')
        : '✗ No existe el chat #' + ia[1]);
      return ok;
    }
    if (/^\/(start|ayuda|help)\b/i.test(texto)){
      await decir('Para contestar a un cliente de la tienda, <b>responde</b> (desliza el mensaje o mantén presionado → Responder) al aviso <b>💬 Chat #…</b>.\nTambién puedes escribir <code>#12 tu mensaje</code>.\n/chats muestra los últimos chats.\nCuando respondes un chat, la IA deja de contestar en él. <code>/ia 12</code> la vuelve a encender (<code>/ia 12 off</code> la apaga).');
      return ok;
    }

    // ¿A qué chat va? 1) respuesta a un aviso "Chat #12"  2) mensaje que empieza con "#12 "
    let chatId = null, cuerpo = texto;
    const ref = msg.reply_to_message && (msg.reply_to_message.text || msg.reply_to_message.caption || '');
    const m = ref && ref.match(/chat #(\d+)/i);
    if (m) chatId = Number(m[1]);
    else {
      const d = texto.match(/^#(\d+)\s+([\s\S]+)$/);
      if (d){ chatId = Number(d[1]); cuerpo = d[2].trim(); }
    }

    if (!chatId){
      // Mensaje suelto: no sabemos a qué cliente va.
      if (texto) await decir('No sé a qué cliente va este mensaje. <b>Responde</b> al aviso <b>💬 Chat #…</b> o escribe <code>#12 tu mensaje</code>. /chats para ver los últimos.');
      return ok;
    }
    if (!cuerpo){
      await decir('Por ahora el chat de la tienda solo envía texto (no fotos, notas de voz ni archivos).');
      return ok;
    }

    const r = await rpc(env, 'chat_responder', { p_chat: chatId, p_texto: cuerpo });
    if (!r || !r.ok){
      await decir('✗ ' + esc((r && r.error) || 'No se pudo enviar'));
      return ok;
    }
    // Confirmación discreta: una reacción 👍 en tu mensaje (si falla, un texto corto).
    const reac = await tg(env, 'setMessageReaction', {
      chat_id: msg.chat.id, message_id: msg.message_id, reaction: [{ type: 'emoji', emoji: '👍' }],
    });
    if (!reac.ok) await decir('✓ Enviado al chat #' + chatId);
  } catch (e){
    await decir('✗ Error enviando al chat: ' + esc(e.message));
  }
  return ok;
}
