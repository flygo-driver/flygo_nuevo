import nodemailer from "nodemailer";

type MailCfg = {
  host: string;
  port: number;
  user: string;
  pass: string;
  secure: boolean;
  from: string;
  to: string[];
};

function env(name: string): string {
  return String(process.env[name] ?? "").trim();
}

export function readMailConfig(): MailCfg | null {
  const host = env("SMTP_HOST");
  const portRaw = env("SMTP_PORT");
  const user = env("SMTP_USER");
  const pass = env("SMTP_PASS");
  const secureRaw = env("SMTP_SECURE");
  const from = env("SMTP_FROM") || user;
  const toRaw = env("ALERTS_TO");

  const port = portRaw ? Number(portRaw) : 587;
  const secure = secureRaw === "true" || secureRaw === "1";
  const to = toRaw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  if (!host || !user || !pass || !from || to.length === 0) return null;
  if (!Number.isFinite(port) || port <= 0) return null;

  return { host, port, user, pass, secure, from, to };
}

export async function sendMail(params: { subject: string; text: string }): Promise<void> {
  const cfg = readMailConfig();
  if (!cfg) {
    console.warn("[mail] SMTP no configurado. Define SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS/SMTP_FROM y ALERTS_TO.");
    return;
  }

  const transport = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.secure,
    auth: { user: cfg.user, pass: cfg.pass },
  });

  await transport.sendMail({
    from: cfg.from,
    to: cfg.to.join(","),
    subject: params.subject,
    text: params.text,
  });
}

