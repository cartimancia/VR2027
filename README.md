# veraricardo.pt

Wedding site for Vera & Ricardo, 1 May 2027. Static site on GitHub Pages; RSVPs in Supabase.

| File | What |
|---|---|
| `index.html` | Front page: video, names, countdown, "Entrar" link. Wedding date in `WEDDING` at the bottom. |
| `entrar.html` | Guest sign-in (invite code + first name) and RSVP. |
| `admin.html` | Private dashboard: RSVPs, headcount, create invites, export CSV. |
| `supabase-config.js` | Supabase URL + public key, shared by both pages. |
| `supabase/schema.sql` | Tables, security policies and guest functions. |
| `media/hero.mp4` | Hero video (H.264, ~7 MB). `media/hero.jpg` is the poster, sign-in background and share preview. |

## How sign-in works

- **Guests** enter the code from their invitation + their first name. They see everyone in their household, answer yes/no per person, add dietary needs and a message, and can come back to change it. Invite links `https://veraricardo.pt/entrar.html?c=CODE` pre-fill the code (good for a QR code on the invitation).
- **Admins** (you and Vera) sign in on `/admin.html` with email + password.
- Guests never get table access. Two database functions check code + name and only touch that household. Admin access is limited to emails in the `admins` table.

## Supabase setup (once)

1. Create a project at supabase.com. Pick an **EU region** (guest names and dietary info are personal data).
2. **SQL Editor** → paste `supabase/schema.sql` → Run.
3. **Authentication → Users → Add user**: create a user for each of you (email + password, "Auto confirm").
4. Back in SQL Editor:
   ```sql
   insert into public.admins(email) values ('your@email'), ('vera@email');
   ```
5. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up", so nobody else can create an account.
6. **Project Settings → API**: copy the Project URL and the `anon`/publishable key into `supabase-config.js`. Never the `service_role`/secret key.
7. Push. Open `/admin.html`, sign in, create invites with "Novo convite", copy each invite's link or code onto the invitation.

## Things to know

- **Free tier pauses** after about a week without database activity; guests would then see "Não foi possível ligar". `.github/workflows/keepalive.yml` pings the database every 3 days to prevent that. A failed run (e.g. project already paused) emails you; restore the project in the Supabase dashboard. GitHub switches off scheduled workflows in repos with no commits for 60 days. It emails a warning first; re-enable it in the Actions tab with one click.
- Name matching ignores case and accents and accepts the first name or full name ("joao" matches "João Pedro Silva").
- Codes are 8 characters without look-alikes (no 0/O/1/I).
- The CSV export uses `;` so it opens correctly in Portuguese Excel.
