// Cloudflare Worker: keeps your Google key off the phone.
// Deploy: npx wrangler deploy ; then: npx wrangler secret put GOOGLE_KEY
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

async function story(lat, lng) {
  try {
    const g = await (await fetch(`https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=${lat}|${lng}&gsradius=300&gslimit=1&format=json`)).json();
    const t = g.query.geosearch[0]?.title;
    if (!t) return '';
    const s = await (await fetch('https://en.wikipedia.org/api/rest_v1/page/summary/' + encodeURIComponent(t))).json();
    return s.extract || '';
  } catch { return ''; }
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method !== 'POST' || url.pathname !== '/locate') return new Response('ok');
    // TODO: rate-limit per device/IP (e.g. Workers rate limiting) so nobody can run up your Google bill.
    const { lat, lng, text } = await req.json();
    if (typeof lat !== 'number' || typeof lng !== 'number') return json({ error: 'bad request' }, 400);
    const circle = { circle: { center: { latitude: lat, longitude: lng }, radius: 150 } };
    const q = (text || '').trim().slice(0, 100);
    const [endpoint, body] = q
      ? ['places:searchText', { textQuery: q, locationBias: circle, maxResultCount: 1 }]
      : ['places:searchNearby', { locationRestriction: circle, maxResultCount: 1 }];
    const r = await fetch('https://places.googleapis.com/v1/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': env.GOOGLE_KEY, 'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location' },
      body: JSON.stringify(body),
    });
    const p = (await r.json()).places?.[0];
    if (!p) return json({ error: 'none' }, 404);
    const plat = p.location.latitude, plng = p.location.longitude;
    return json({ name: p.displayName.text, address: p.formattedAddress, lat: plat, lng: plng, story: await story(plat, plng) });
  },
};
