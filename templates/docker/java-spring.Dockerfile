# Talay Java/Spring Boot imajı (Maven). Gradle için build stage: COPY gradle/ gradlew build.gradle* settings.gradle* → ./gradlew bootJar
# Java sürümünü projeyle eşle (21 veya 25) ve CI'daki java-version ile aynı tut.
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /build
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN ./mvnw --batch-mode --no-transfer-progress dependency:go-offline
COPY src ./src
RUN ./mvnw --batch-mode --no-transfer-progress package -DskipTests

FROM eclipse-temurin:21-jre-alpine
RUN apk upgrade --no-cache \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app
WORKDIR /app
COPY --chown=10001:10001 --from=build /build/target/*.jar app.jar
ENV SPRING_PROFILES_ACTIVE=prod
USER 10001:10001
EXPOSE 8080
# OTel Java agent'ı chart JAVA_TOOL_OPTIONS ile ekler; burada ekleme.
ENTRYPOINT ["java","-jar","/app/app.jar"]
