const allowedOrigin = "https://goals-study-desk.exquisitearia2.chatgpt.site";
const url = Deno.env.get("SUPABASE_URL")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "apikey, content-type",
  "Vary": "Origin",
};
const privateHeaders = {
  "Content-Type": "application/json",
  "apikey": serviceRole,
  "Authorization": "Bearer " + serviceRole,
};

function reply(status: number, message: string): Response {
  return Response.json({ message }, { status, headers: cors });
}

async function claim(code: string, release = false): Promise<boolean> {
  const result = await fetch(url + "/rest/v1/rpc/goals_claim_enrollment", {
    method: "POST", headers: privateHeaders,
    body: JSON.stringify({ code, release_claim: release }),
  });
  return result.ok && await result.json() === true;
}

Deno.serve(async request => {
  if (request.headers.get("origin") !== allowedOrigin) return reply(403, "来源无效。");
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return reply(405, "请求方式无效。");
  try {
    const payload = await request.text();
    if (payload.length > 2048) return reply(400, "注册信息无效。");
    const { email, password, code } = JSON.parse(payload);
    if (typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email) ||
        typeof password !== "string" || password.length < 10 || password.length > 72 ||
        typeof code !== "string" || !/^[0-9a-f-]{36}$/iu.test(code)) {
      return reply(400, "请检查邮箱、邀请码和至少 10 位的密码。");
    }
    if (!(await claim(code))) return reply(403, "注册邀请码无效、已使用或过期。");
    const account = await fetch(url + "/auth/v1/admin/users", {
      method: "POST", headers: privateHeaders,
      body: JSON.stringify({ email, password, email_confirm: true }),
    });
    if (!account.ok) {
      await claim(code, true);
      return reply(400, "无法创建账号。请检查邮箱和密码，或使用已有账号登录。");
    }
    return reply(201, "账号已创建。");
  } catch {
    return reply(503, "注册服务暂时不可用，请稍后再试。");
  }
});
