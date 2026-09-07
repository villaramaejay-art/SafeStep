# Supabase Setup

SafeStep stores emergency contacts and safe spaces in Supabase, scoped to the
signed-in user by row level security.

## 1. Create the project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard) and create a project.
2. Wait for provisioning to finish.

## 2. Create the tables

1. Open **SQL Editor -> New query**.
2. Paste the whole of [`supabase/schema.sql`](supabase/schema.sql) and run it.

It is safe to re-run. It creates:

| Object | Purpose |
| --- | --- |
| `profiles` | First name, last name and phone from the registration form |
| `contacts` | Emergency contacts, one row per person |
| `safe_spaces` | Geofenced areas with a radius in km |
| `alerts` | A record of every emergency SMS the app sent |
| RLS policies | Every query is limited to `auth.uid() = user_id` |
| `contacts_single_primary` trigger | Promoting a contact demotes the previous primary |
| `on_auth_user_created_profile` trigger | Saves the registration details alongside the new account |

## 3. Configure email auth

Under **Authentication -> Providers -> Email**, make sure Email is enabled.

For development, turn **Confirm email** *off* so a new account can sign in
straight away. With it on, registration still works but the app will tell the
user to confirm by email before signing in.

## 4. Copy your credentials

**Project Settings -> API**:

- **Project URL** -> `SUPABASE_URL`
- **anon public** (newer projects call it **publishable key**) -> `SUPABASE_ANON_KEY`

The anon/publishable key is designed to ship inside client apps. It is not a
secret: row level security is what protects the data. The **service_role** key
is a secret and must never go in this app.

## 5. Run the app

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Same flags for `flutter build apk`, `flutter build web`, and `flutter test`.

Launching without them is safe: the app shows a screen explaining what is
missing instead of crashing.

### Keeping the flags handy

To avoid retyping, put them in a JSON file and pass it instead:

```jsonc
// supabase.local.json  (add to .gitignore)
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_ANON_KEY"
}
```

```bash
flutter run --dart-define-from-file=supabase.local.json
```

In VS Code, add the same flags to `.vscode/launch.json` under `"args"`.

## Verifying it works

1. Register a new account in the app.
2. In Supabase, open **Table Editor -> safe_spaces**: three rows (Home, Work,
   Gym) should already exist for that user.
3. Add an emergency contact, then check **Table Editor -> contacts**.
4. Mark a second contact as primary and refresh the table: the first one should
   have flipped to `secondary` on its own.

## Troubleshooting

| Message | Cause |
| --- | --- |
| "SafeStep cannot start" | No `--dart-define` values were passed |
| "The contacts table is missing. Run supabase/schema.sql first." | Step 2 was skipped |
| "Confirm your email address first, then sign in." | Email confirmation is on (step 3) |
| "You already have a safe space with that name." | Names are unique per user, case-insensitively |
| Empty lists but no error | Signed in as a different account than the one holding the rows |
