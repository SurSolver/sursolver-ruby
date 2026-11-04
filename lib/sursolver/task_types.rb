# frozen_string_literal: true

# Generated from the SurSolver catalog (GET /v1/task-types) by the spec repository
# tools/templates/rubygems.ts. Catalog fetched at 2026-11-03T21:16:22.334Z. DO NOT EDIT.

module SurSolver
  # Every accepted task.type spelling: canonical names, ProxyLess twins and aliases.
  module TaskTypes
    AKAMAI_BMP_TASK = "AkamaiBmpTask"
    AKAMAI_COOKIE = "AkamaiCookie"
    AKAMAI_COOKIE_PROXY_LESS = "AkamaiCookieProxyLess"
    AKAMAI_SBSD_COOKIE = "AkamaiSbsdCookie"
    ALTCHA_TOKEN = "AltchaToken"
    ALTCHA_TOKEN_PROXY_LESS = "AltchaTokenProxyLess"
    AWS_CAPTCHA_COOKIE = "AwsCaptchaCookie"
    AWS_CHALLENGE_COOKIE = "AwsChallengeCookie"
    CAPTCHA_FOX_TOKEN = "CaptchaFoxToken"
    CASTLE_ANDROID_TOKEN = "CastleAndroidToken"
    CASTLE_TOKEN = "CastleToken"
    CASTLE_WEB_TOKEN = "CastleWebToken"
    CLOUDFLARE_CHALLENGE_COOKIE = "CloudflareChallengeCookie"
    DATA_DOME_SLIDER_COOKIE = "DataDomeSliderCookie"
    FRIENDLY_CAPTCHA_TOKEN = "FriendlyCaptchaToken"
    FRIENDLY_CAPTCHA_TOKEN_PROXY_LESS = "FriendlyCaptchaTokenProxyLess"
    GEE_TEST_TOKEN = "GeeTestToken"
    GEE_TEST_TOKEN_PROXY_LESS = "GeeTestTokenProxyLess"
    GEE_TEST_V3_TOKEN = "GeeTestV3Token"
    GEE_TEST_V4_TOKEN = "GeeTestV4Token"
    IMAGE_TO_TEXT = "ImageToText"
    IMAGE_TO_TEXT_TASK = "ImageToTextTask"
    IMPERVA_COOKIE = "ImpervaCookie"
    IMPERVA_UTMVC_COOKIE = "ImpervaUtmvcCookie"
    KASADA_TOKEN = "KasadaToken"
    KASADA_TOKEN_PROXY_LESS = "KasadaTokenProxyLess"
    LEMIN_TOKEN = "LeminToken"
    LEMIN_TOKEN_PROXY_LESS = "LeminTokenProxyLess"
    MT_CAPTCHA_TOKEN = "MtCaptchaToken"
    MT_CAPTCHA_TOKEN_PROXY_LESS = "MtCaptchaTokenProxyLess"
    PERIMETER_X_COOKIE = "PerimeterXCookie"
    PROSOPO_TOKEN = "ProsopoToken"
    PROSOPO_TOKEN_PROXY_LESS = "ProsopoTokenProxyLess"
    RE_CAPTCHA_V2_ENTERPRISE_TOKEN = "ReCaptchaV2EnterpriseToken"
    RE_CAPTCHA_V2_ENTERPRISE_TOKEN_PROXY_LESS = "ReCaptchaV2EnterpriseTokenProxyLess"
    RE_CAPTCHA_V2_TOKEN = "ReCaptchaV2Token"
    RE_CAPTCHA_V2_TOKEN_PROXY_LESS = "ReCaptchaV2TokenProxyLess"
    RE_CAPTCHA_V3_ENTERPRISE_TOKEN = "ReCaptchaV3EnterpriseToken"
    RE_CAPTCHA_V3_ENTERPRISE_TOKEN_PROXY_LESS = "ReCaptchaV3EnterpriseTokenProxyLess"
    RE_CAPTCHA_V3_TOKEN = "ReCaptchaV3Token"
    RE_CAPTCHA_V3_TOKEN_PROXY_LESS = "ReCaptchaV3TokenProxyLess"
    SHAPE_COOKIE = "ShapeCookie"
    SHAPE_COOKIE_PROXY_LESS = "ShapeCookieProxyLess"
    TURNSTILE_TOKEN = "TurnstileToken"
    TURNSTILE_TOKEN_PROXY_LESS = "TurnstileTokenProxyLess"
    VERCEL_COOKIE = "VercelCookie"
  end

  # The complete errorCode vocabulary of the solver endpoints.
  module ErrorCodes
    ERROR_KEY_DOES_NOT_EXIST = "ERROR_KEY_DOES_NOT_EXIST"
    ERROR_WRONG_CLIENT_KEY = "ERROR_WRONG_CLIENT_KEY"
    ERROR_ZERO_BALANCE = "ERROR_ZERO_BALANCE"
    ERROR_NO_SLOT_AVAILABLE = "ERROR_NO_SLOT_AVAILABLE"
    ERROR_TYPE_NOT_SUPPORTED = "ERROR_TYPE_NOT_SUPPORTED"
    ERROR_TASK_NOT_FOUND = "ERROR_TASK_NOT_FOUND"
    ERROR_TASK_EXPIRED = "ERROR_TASK_EXPIRED"
    ERROR_TASK_TIMEOUT = "ERROR_TASK_TIMEOUT"
    ERROR_FAILED = "ERROR_FAILED"
    ERROR_INVALID_REQUEST = "ERROR_INVALID_REQUEST"
    ERROR_WRONG_USERAGENT = "ERROR_WRONG_USERAGENT"
    ERROR_INTERNAL_ERROR = "ERROR_INTERNAL_ERROR"

    # All codes in catalog order.
    ALL = [ERROR_KEY_DOES_NOT_EXIST, ERROR_WRONG_CLIENT_KEY, ERROR_ZERO_BALANCE, ERROR_NO_SLOT_AVAILABLE, ERROR_TYPE_NOT_SUPPORTED, ERROR_TASK_NOT_FOUND, ERROR_TASK_EXPIRED, ERROR_TASK_TIMEOUT, ERROR_FAILED, ERROR_INVALID_REQUEST, ERROR_WRONG_USERAGENT, ERROR_INTERNAL_ERROR].freeze
  end
end
