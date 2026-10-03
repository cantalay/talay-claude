# Java / Spring Boot standardı

Referans uygulama: `cantalay/todogi-be` (Maven, Java 21, Flyway, Spring Security resource server).

## Bağımlılıklar
- `spring-boot-starter-web`, `spring-boot-starter-actuator`, `micrometer-registry-prometheus`
- `spring-boot-starter-oauth2-resource-server` (auth varsa)
- `spring-boot-starter-data-jpa` veya `-jdbc`, `org.postgresql:postgresql`, `flyway-core`, `flyway-database-postgresql`
- `spring-boot-starter-data-redis` (Redis varsa)
- OTel bağımlılığı **ekleme** — chart Java agent'ı (2.31.1) init container ile enjekte eder (`runtime.java.agent.enabled: true`).

## application-prod.yml
```yaml
server:
  port: ${SERVER_PORT:8080}
  shutdown: graceful
spring:
  lifecycle.timeout-per-shutdown-phase: 30s
  datasource:            # SPRING_DATASOURCE_URL/USERNAME/PASSWORD Vault'tan env olarak gelir
    hikari:
      maximum-pool-size: 8
  jpa:
    open-in-view: false
    hibernate.ddl-auto: validate   # şema Flyway'de
  flyway:
    enabled: true
    locations: classpath:db/migration
  data.redis:
    url: ${REDIS_URL:}
  security.oauth2.resourceserver.jwt:
    issuer-uri: ${KEYCLOAK_ISSUER_URI}        # https://auth.cantalay.com/realms/<project>
    audiences: ${KEYCLOAK_AUDIENCE}           # <project>-api
management:
  endpoints.web.exposure.include: health,prometheus,info
  endpoint.health.probes.enabled: true
  health.livenessstate.enabled: true
  health.readinessstate.enabled: true
  endpoint.health.group.readiness.include: readinessState,db,redis
  metrics.tags.application: ${OTEL_SERVICE_NAME:app}
logging:
  structured.format.console: ecs     # Spring Boot ≥3.4: JSON stdout; agent MDC'ye trace_id/span_id koyar
```
Values: probes `startup`/`liveness` → `/actuator/health/liveness`, `readiness` → `/actuator/health/readiness`,
`serviceMonitor.path: /actuator/prometheus`. Actuator yollarını `SecurityFilterChain`'de `permitAll` yap.

## Roller
```java
@Bean
JwtAuthenticationConverter jwtAuthenticationConverter() {
  var converter = new JwtAuthenticationConverter();
  converter.setJwtGrantedAuthoritiesConverter(jwt -> {
    Map<String, Object> realm = jwt.getClaimAsMap("realm_access");
    Collection<String> roles = realm == null ? List.of() : (Collection<String>) realm.getOrDefault("roles", List.of());
    return roles.stream().map(r -> (GrantedAuthority) new SimpleGrantedAuthority("ROLE_" + r)).toList();
  });
  return converter;
}
```
`@PreAuthorize("hasRole('admin')")` ile kullan.

## Migration
`src/main/resources/db/migration/V1__init.sql`, `V2__…`. Flyway startup'ta çalışır (tek replika; çok replikada Flyway
kendi lock'unu kullanır). Kolon silme/yeniden adlandırma iki sürümde (expand/contract).

## Dockerfile
`templates/docker/java-spring.Dockerfile` (Maven) — Gradle için build stage'i `./gradlew bootJar` ile değiştir.
CI: `talay-workflows/java.yaml`, `build-tool: maven|gradle`, `java-version` projedekiyle aynı (21 veya 25).

## Values özeti
```yaml
runtime: { type: java, java: { agent: { enabled: true } } }
containerPort: 8080
config: { SPRING_PROFILES_ACTIVE: prod, SERVER_PORT: "8080", KEYCLOAK_ISSUER_URI: …, KEYCLOAK_AUDIENCE: … }
resources: { requests: { cpu: 50m, memory: 320Mi }, limits: { memory: 768Mi } }
```
JVM bellek: `runtime.java.toolOptions: "-XX:MaxRAMPercentage=70"`.
