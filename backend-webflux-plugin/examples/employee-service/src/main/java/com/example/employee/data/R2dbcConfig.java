package com.example.employee.data;

import io.r2dbc.spi.ConnectionFactory;
import java.util.List;
import java.util.UUID;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.data.convert.ReadingConverter;
import org.springframework.data.convert.WritingConverter;
import org.springframework.data.r2dbc.convert.R2dbcCustomConversions;
import org.springframework.data.r2dbc.dialect.DialectResolver;

/**
 * UUID columns are CHAR(36). Spring Data R2DBC passes java.util.UUID through to the driver
 * untouched, and io.asyncer:r2dbc-mysql ships no UUID codec, so without these converters the
 * first save() or findByExternalId(UUID) against MySQL fails with "Cannot encode". H2 binds UUID
 * natively, which is exactly why the sample would not have shown it.
 */
@Configuration
public class R2dbcConfig {

    @Bean
    public R2dbcCustomConversions r2dbcCustomConversions(ConnectionFactory connectionFactory) {
        return R2dbcCustomConversions.of(
            DialectResolver.getDialect(connectionFactory),
            List.of(new UuidToStringConverter(), new StringToUuidConverter()));
    }

    @WritingConverter
    static final class UuidToStringConverter implements Converter<UUID, String> {
        @Override
        public String convert(UUID source) {
            return source.toString();
        }
    }

    @ReadingConverter
    static final class StringToUuidConverter implements Converter<String, UUID> {
        @Override
        public UUID convert(String source) {
            return UUID.fromString(source);
        }
    }
}
