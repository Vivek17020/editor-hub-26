-- Create the trigger on auth.users to automatically create profiles
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Update the handle_new_user function to work with current profiles table
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
declare
  raw_meta jsonb;
  name text;
  avatar text;
begin
  -- Ensure raw_user_meta_data is valid jsonb
  raw_meta := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  name := coalesce(raw_meta->>'full_name', raw_meta->>'name', new.email);
  avatar := coalesce(raw_meta->>'avatar_url', raw_meta->>'picture', null);

  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, name, avatar)
  on conflict (id) do update
    set full_name = excluded.full_name,
        avatar_url = excluded.avatar_url,
        updated_at = now();

  return new;
end;
$$;