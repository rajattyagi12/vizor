<#outputformat "plainText">

<#assign fixedLink = link?replace("http://keycloak:8080", "http://127.0.0.1:4500")>

<#assign requiredActionsText>
  <#if requiredActions??>
    <#list requiredActions><#items as reqActionItem>
      ${msg("requiredAction.${reqActionItem}")}<#sep>, </#sep>
    </#items></#list>
  </#if>
</#assign>

</#outputformat>

<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("executeActionsBodyHtml", fixedLink, linkExpiration, realmName, linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
