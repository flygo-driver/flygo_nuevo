const urls = [
  "https://flygo-rd.web.app/azul/preview-post",
  "https://flygo-rd.web.app/azul/preview-post/",
  "https://us-central1-flygo-rd.cloudfunctions.net/azulPreviewDemo",
];

for (const url of urls) {
  const res = await fetch(url, { redirect: "follow" });
  const html = await res.text();
  const action = html.match(/action="([^"]+)"/)?.[1] ?? "(sin form)";
  const merchant = html.match(/name="MerchantId" value="([^"]+)"/)?.[1] ?? "(sin merchant)";
  const has999 = html.includes("99999999999");
  const hasRefresh = html.includes("http-equiv=\"refresh\"");
  console.log("\nURL:", url);
  console.log("  status:", res.status, "final:", res.url);
  console.log("  action:", action);
  console.log("  merchant:", merchant);
  console.log("  demo999:", has999, "metaRefresh:", hasRefresh);
}
