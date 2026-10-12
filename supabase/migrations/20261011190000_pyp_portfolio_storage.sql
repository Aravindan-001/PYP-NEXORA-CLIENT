-- PYP: Supabase Storage Bucket & RLS Policies for Photographer Portfolios
-- Forward-only migration

-- 1. Create portfolio_images bucket in storage.buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'portfolio_images',
  'portfolio_images',
  true,
  10485760, -- 10MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- 2. Storage RLS Policies for portfolio_images
DROP POLICY IF EXISTS "Public can view portfolio images" ON storage.objects;
DROP POLICY IF EXISTS "Photographers can upload portfolio images to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Photographers can update own portfolio images" ON storage.objects;
DROP POLICY IF EXISTS "Photographers can delete own portfolio images" ON storage.objects;

-- SELECT policy: Public can view portfolio images
CREATE POLICY "Public can view portfolio images"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'portfolio_images');

-- INSERT policy: Authenticated photographers can upload to their own folder
CREATE POLICY "Photographers can upload portfolio images to own folder"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- UPDATE policy: Authenticated photographers can update files in their own folder
CREATE POLICY "Photographers can update own portfolio images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  )
  WITH CHECK (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- DELETE policy: Authenticated photographers can delete files in their own folder
CREATE POLICY "Photographers can delete own portfolio images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- 3. Update register_as_photographer RPC to optionally accept p_portfolio_urls
DROP FUNCTION IF EXISTS public.register_as_photographer(text, text, text, text, integer, text, text);

CREATE OR REPLACE FUNCTION public.register_as_photographer(
  p_display_name text,
  p_bio text,
  p_city text,
  p_category text,
  p_starting_price_paise integer,
  p_phone text,
  p_email text,
  p_portfolio_urls text[] DEFAULT '{}'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_clean_display_name text := trim(coalesce(p_display_name, ''));
  v_clean_city text := trim(coalesce(p_city, ''));
  v_clean_category text := trim(coalesce(p_category, ''));
  v_clean_bio text := trim(coalesce(p_bio, ''));
  v_clean_phone text := trim(coalesce(p_phone, ''));
  v_clean_email text := trim(coalesce(p_email, ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthenticated user';
  END IF;

  IF length(v_clean_display_name) < 2 OR length(v_clean_display_name) > 100 THEN
    RAISE EXCEPTION 'Display name must be between 2 and 100 characters';
  END IF;

  IF length(v_clean_city) < 2 OR length(v_clean_city) > 100 THEN
    RAISE EXCEPTION 'City must be between 2 and 100 characters';
  END IF;

  IF length(v_clean_category) < 2 OR length(v_clean_category) > 50 THEN
    RAISE EXCEPTION 'Category must be between 2 and 50 characters';
  END IF;

  IF p_starting_price_paise < 0 OR p_starting_price_paise > 100000000 THEN
    RAISE EXCEPTION 'Starting price must be between 0 and 1,000,000 INR';
  END IF;

  IF length(v_clean_phone) < 8 OR length(v_clean_phone) > 20 THEN
    RAISE EXCEPTION 'Phone number must be valid';
  END IF;

  IF v_clean_email !~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Valid email address is required';
  END IF;

  -- Create or update photographer profile (is_published remains unchanged on update)
  INSERT INTO public.photographer_profiles (
    user_id, display_name, bio, city, category, starting_price_paise, portfolio_urls, is_published
  )
  VALUES (
    v_user_id, v_clean_display_name, v_clean_bio, v_clean_city, v_clean_category, p_starting_price_paise, coalesce(p_portfolio_urls, '{}'), false
  )
  ON CONFLICT (user_id) DO UPDATE SET
    display_name = excluded.display_name,
    bio = excluded.bio,
    city = excluded.city,
    category = excluded.category,
    starting_price_paise = excluded.starting_price_paise,
    portfolio_urls = excluded.portfolio_urls,
    updated_at = now()
  RETURNING id INTO v_profile_id;

  -- Add photographer role
  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_user_id, 'photographer')
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Upsert private details
  INSERT INTO public.photographer_private_details (photographer_id, phone, email)
  VALUES (v_profile_id, v_clean_phone, v_clean_email)
  ON CONFLICT (photographer_id) DO UPDATE SET
    phone = excluded.phone,
    email = excluded.email,
    updated_at = now();

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.register_as_photographer(text, text, text, text, integer, text, text, text[]) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_as_photographer(text, text, text, text, integer, text, text, text[]) TO authenticated;
