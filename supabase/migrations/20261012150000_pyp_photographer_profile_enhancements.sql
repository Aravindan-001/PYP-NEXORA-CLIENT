-- Migration: 20261012150000_pyp_photographer_profile_enhancements.sql
-- Description: Enhances register_as_photographer RPC to support experience_years, specializations, service_locations, and availability_note.

DROP FUNCTION IF EXISTS public.register_as_photographer(text, text, text, text, integer, text, text, text[]);
DROP FUNCTION IF EXISTS public.register_as_photographer(text, text, text, text, integer, text, text, text[], integer, text[], text[], text);

CREATE OR REPLACE FUNCTION public.register_as_photographer(
  p_display_name text,
  p_bio text,
  p_city text,
  p_category text,
  p_starting_price_paise integer,
  p_phone text,
  p_email text,
  p_portfolio_urls text[] DEFAULT '{}',
  p_experience_years integer DEFAULT 0,
  p_specializations text[] DEFAULT '{}',
  p_service_locations text[] DEFAULT '{}',
  p_availability_note text DEFAULT NULL
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
  v_clean_avail_note text := nullif(trim(coalesce(p_availability_note, '')), '');
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

  -- Upsert photographer profile
  INSERT INTO public.photographer_profiles (
    user_id,
    display_name,
    bio,
    city,
    category,
    starting_price_paise,
    portfolio_urls,
    experience_years,
    specializations,
    service_locations,
    availability_note,
    is_published
  )
  VALUES (
    v_user_id,
    v_clean_display_name,
    v_clean_bio,
    v_clean_city,
    v_clean_category,
    p_starting_price_paise,
    coalesce(p_portfolio_urls, '{}'),
    greatest(0, coalesce(p_experience_years, 0)),
    coalesce(p_specializations, '{}'),
    coalesce(p_service_locations, '{}'),
    v_clean_avail_note,
    false
  )
  ON CONFLICT (user_id) DO UPDATE SET
    display_name = excluded.display_name,
    bio = excluded.bio,
    city = excluded.city,
    category = excluded.category,
    starting_price_paise = excluded.starting_price_paise,
    portfolio_urls = excluded.portfolio_urls,
    experience_years = excluded.experience_years,
    specializations = excluded.specializations,
    service_locations = excluded.service_locations,
    availability_note = excluded.availability_note,
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

REVOKE ALL ON FUNCTION public.register_as_photographer FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_as_photographer TO authenticated;
