/** Simula el POST del navegador a AZUL sandbox y reporta si abre o error. */
const demoUrl = process.argv[2] || "https://us-central1-flygo-rd.cloudfunctions.net/azulPreviewDemo";

const res = await fetch(demoUrl);
const html = await res.text();
const action = html.match(/action="([^"]+)"/)?.[1];
if (!action) {
  console.error("No form action in HTML");
  process.exit(1);
}

const fields = {};
for (const m of html.matchAll(/name="([^"]+)" value="([^"]*)"/g)) {
  fields[m[1]] = m[2];
}

console.log("POST ->", action);
console.log("MerchantId:", fields.MerchantId);
console.log("OrderNumber:", fields.OrderNumber);
console.log("Amount:", fields.Amount, "ITBIS:", fields.ITBIS);
console.log("AuthHash len:", fields.AuthHash?.length ?? 0);

const body = new URLSearchParams(fields);
const postRes = await fetch(action, {
  method: "POST",
  headers: {
    "Content-Type": "application/x-www-form-urlencoded",
    "User-Agent": "RAI-AZUL-Check/1.0",
  },
  body,
  redirect: "manual",
});

console.log("\nAZUL response:");
console.log("  status:", postRes.status);
console.log("  location:", postRes.headers.get("location") ?? "(none)");
const snippet = (await postRes.text()).slice(0, 500);
if (snippet.includes("INVALID_MERCHANTID")) console.log("  BODY: INVALID_MERCHANTID");
else if (snippet.includes("Error.aspx")) console.log("  BODY: Error.aspx page");
else if (snippet.includes("pas.azul.com.do")) console.log("  BODY: pas.azul.com.do error");
else if (snippet.includes("pruebas.azul.com.do")) console.log("  BODY: pruebas page OK fragment");
else console.log("  BODY snippet:", snippet.replace(/\s+/g, " ").slice(0, 200));
