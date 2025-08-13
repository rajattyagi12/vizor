<#assign fixedLink = link?replace("http://keycloak:8080", "http://127.0.0.1:4500")>
<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("emailVerificationBodyHtml", fixedLink, linkExpiration, realmName, linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
