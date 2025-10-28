from rest_framework_simplejwt.authentication import JWTAuthentication


class JSONWebTokenAuthenticationQS(JWTAuthentication):
    """
    JWT authentication that accepts tokens from query string parameter 'jwt'
    instead of Authorization header
    """
    def get_raw_token(self, request):
        # Check query parameters first
        token = request.query_params.get('jwt')
        if token:
            return token.encode('utf-8') if isinstance(token, str) else token
        # Fall back to standard header-based authentication
        return super().get_raw_token(request)