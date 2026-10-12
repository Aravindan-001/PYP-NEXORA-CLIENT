-- PYP: Storage Security Hardening & Role Enforcement
-- Forward-only migration

-- 1. Re-define Storage RLS Policies for portfolio_images bucket enforcing photographer role
DROP POLICY IF EXISTS "Photographers can upload portfolio images to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Photographers can update own portfolio images" ON storage.objects;
DROP POLICY IF EXISTS "Photographers can delete own portfolio images" ON storage.objects;

-- INSERT policy: Only authenticated photographers can upload to their own folder
CREATE POLICY "Photographers can upload portfolio images to own folder"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
    AND private.is_photographer((select auth.uid()))
  );

-- UPDATE policy: Only authenticated photographers can update files in their own folder
CREATE POLICY "Photographers can update own portfolio images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
    AND private.is_photographer((select auth.uid()))
  )
  WITH CHECK (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
    AND private.is_photographer((select auth.uid()))
  );

-- DELETE policy: Only authenticated photographers can delete files in their own folder
CREATE POLICY "Photographers can delete own portfolio images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'portfolio_images'
    AND (storage.foldername(name))[1] = (select auth.uid())::text
    AND private.is_photographer((select auth.uid()))
  );

-- 2. Clean up legacy admin_moderate_photographer function
DROP FUNCTION IF EXISTS public.admin_moderate_photographer(uuid, boolean);
