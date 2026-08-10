-- Clock-in photos: tighten INSERT policy so only company members
-- can upload into their own company's folder.
--
-- Path format: {companyId}/{userId}/{timestamp}.jpg
-- The first folder segment is the company UUID, so we scope uploads
-- to authenticated users who are members of that company.

DROP POLICY IF EXISTS "clock_in_photos_insert" ON storage.objects;

CREATE POLICY "clock_in_photos_insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'clock-in-photos'::text
  AND is_company_member((storage.foldername(name))[1]::uuid)
);
