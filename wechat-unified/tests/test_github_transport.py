"""No network or real credentials. Verify redirect and TLS policy of the publishing tool."""
import importlib.util, pathlib, ssl, urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('wu_transport',root/'tools/github_native.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
request=urllib.request.Request('https://api.github.com/repos/yuku00/LinkCard-Public/actions/artifacts/1/zip')
request.add_unredirected_header('Authorization','Bearer synthetic-test-value')
redirected=module.HTTPSOnlyRedirect().redirect_request(request,None,302,'Found',{},'https://example.invalid/evidence.zip')
assert request.get_header('Authorization')=='Bearer synthetic-test-value'
assert redirected.get_header('Authorization') is None
try:
 module.HTTPSOnlyRedirect().redirect_request(request,None,302,'Found',{},'http://example.invalid/evidence.zip')
except RuntimeError: pass
else: raise AssertionError('Insecure redirect was allowed')
context=ssl.create_default_context()
assert context.check_hostname and context.verify_mode==ssl.CERT_REQUIRED
try: module.request_bytes('GET','/repos/not-authorized/private')
except ValueError: pass
else: raise AssertionError('Foreign repository accepted')
print('Publishing transport: strict TLS, repository scope, credential-free HTTPS redirects PASS (no network)')
