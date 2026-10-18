// Posts a release to the SuuUI Discord's #releases and pings @Release pings: what's new, with the full notes a click
// away. ci.yml runs it after `wowlua publish` has made the release.
//
// Env: TAG (v0.5.0-beta.1), GITHUB_REPOSITORY, GITHUB_TOKEN, DISCORD_RELEASES_WEBHOOK (secret), DISCORD_RELEASE_ROLE_ID.
// `node discord-release.mjs --dry-run` prints the message instead of posting it.

const { TAG, GITHUB_REPOSITORY, GITHUB_TOKEN, DISCORD_RELEASES_WEBHOOK, DISCORD_RELEASE_ROLE_ID } = process.env;
const dryRun = process.argv.includes("--dry-run");

if (!DISCORD_RELEASES_WEBHOOK && !dryRun) {
  console.log("No DISCORD_RELEASES_WEBHOOK: not posting to Discord.");
  process.exit(0);
}

const res = await fetch(`https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${TAG}`, {
  headers: { Accept: "application/vnd.github+json", ...(GITHUB_TOKEN && { Authorization: `Bearer ${GITHUB_TOKEN}` }) },
});
if (!res.ok) throw new Error(`No release for ${TAG}: ${res.status}`);
const release = await res.json();
const version = TAG.replace(/^v/, "");

// The notes follow CHANGELOG.md: "## <version> (<date>)", an optional intro, then ### New / Changed / Fixed.
const sections = {};
let intro = [];
let current = null;
for (const line of (release.body ?? "").split(/\r?\n/)) {
  const heading = line.match(/^###\s+(.*)/);
  if (heading) { current = heading[1].trim(); sections[current] = []; continue; }
  if (line.startsWith("## ")) continue;
  if (!current) { if (line.trim()) intro.push(line.trim()); continue; }
  if (line.startsWith("- ")) sections[current].push(line.slice(2).trim()); // top-level entries only
}

// One entry's headline: its bold lead ("**Mail window** in SuuUI's look…"), else what comes before its colon
// ("Party frames: …"), else its start.
function headline(entry) {
  const bold = entry.match(/^\*\*(.+?)\*\*/);
  if (bold) return bold[1];
  const colon = entry.indexOf(": ");
  if (colon > 0 && colon <= 50) return entry.slice(0, colon).replace(/\*\*/g, "");
  const plain = entry.replace(/\*\*/g, "");
  return plain.length > 70 ? `${plain.slice(0, 70).replace(/\s+\S*$/, "")}…` : plain;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const news = sections.New ?? [];
const changed = (sections.Changed ?? []).length;
const fixed = (sections.Fixed ?? []).length;
const more = [changed && plural(changed, "change"), fixed && plural(fixed, "fix").replace("fixs", "fixes")].filter(Boolean);
const link = `[All release notes](${release.html_url})`;

const parts = [];
if (intro.length) parts.push(intro.join(" "));
if (news.length) parts.push(`**New**\n${news.map((e) => `• ${headline(e)}`).join("\n")}`);
parts.push(more.length ? `**Also** ${more.join(" and ")}. ${link}` : link);
let description = parts.join("\n\n");
if (description.length > 4000) {
  // Discord's limit is 4096: keep the start of the list and the link.
  description = `${description.slice(0, 3800).replace(/\n[^\n]*$/, "")}\n…\n\n${link}`;
}

const role = DISCORD_RELEASE_ROLE_ID;
const message = {
  content: `${role ? `<@&${role}> ` : ""}**SuuUI ${version}** is out.`,
  allowed_mentions: { roles: role ? [role] : [] },
  embeds: [{
    title: `SuuUI ${version}`,
    url: release.html_url,
    description,
    color: 0xc9a75a, // gilt
    fields: [{
      name: "Get it",
      value: `[CurseForge](https://www.curseforge.com/wow/addons/suuui) · [Wago](https://addons.wago.io/addons/suuui) · [GitHub](${release.html_url})`,
    }],
    footer: { text: release.prerelease ? "Beta: things can still change" : "Release" },
    timestamp: release.published_at ?? undefined,
  }],
};

if (dryRun) {
  console.log(JSON.stringify(message, null, 2));
} else {
  const post = await fetch(`${DISCORD_RELEASES_WEBHOOK}?wait=true`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(message),
  });
  if (!post.ok) throw new Error(`Discord: ${post.status} ${await post.text()}`);
  console.log(`Posted SuuUI ${version} to Discord.`);
}
