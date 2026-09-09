-- Alinha GRANTs de profile/equip com o remoto (authenticated + service_role)
GRANT EXECUTE ON FUNCTION companion_equip_title(text, text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION companion_profile_stats(text) TO service_role, authenticated;
