package cn.sifangguan.hotelaios.shared.security;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertTrue;

class GroupVicePresidentDispatchV53MigrationIntegrationTest {
    private static final String DEMO_TENANT = "10000000-0000-0000-0000-000000000001";
    private static final Set<String> REQUIRED = Set.of("task.create", "task.dispatch");

    @Test
    void v53EnablesVicePresidentQuickDispatchInRoleAndPositionProfiles() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.builder().start()) {
            DataSource dataSource = postgres.getPostgresDatabase();
            Flyway.configure()
                    .dataSource(dataSource)
                    .locations("classpath:db/migration")
                    .cleanDisabled(true)
                    .target("53")
                    .load()
                    .migrate();

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                statement.execute("SELECT set_config('app.tenant_id', '" + DEMO_TENANT + "', false)");
                assertTrue(permissionCodes(statement, """
                        SELECT permission_item.code
                        FROM app_role role
                        JOIN role_permission grant_item
                          ON grant_item.tenant_id = role.tenant_id
                         AND grant_item.role_id = role.id
                        JOIN permission permission_item ON permission_item.id = grant_item.permission_id
                        WHERE role.tenant_id = '%s'::uuid
                          AND role.code = 'GROUP_VICE_PRESIDENT'
                        """.formatted(DEMO_TENANT)).containsAll(REQUIRED));
                assertTrue(permissionCodes(statement, """
                        SELECT DISTINCT permission_item.code
                        FROM position_definition position_item
                        JOIN position_function_profile profile
                          ON profile.tenant_id = position_item.tenant_id
                         AND profile.position_id = position_item.id
                         AND profile.scope_type = 'GROUP'
                        JOIN position_function_profile_version version
                          ON version.tenant_id = profile.tenant_id
                         AND version.profile_id = profile.id
                         AND version.lifecycle_status IN ('PUBLISHED', 'DRAFT')
                        JOIN position_function_profile_permission grant_item
                          ON grant_item.tenant_id = version.tenant_id
                         AND grant_item.profile_version_id = version.id
                        JOIN permission permission_item ON permission_item.id = grant_item.permission_id
                        WHERE position_item.tenant_id = '%s'::uuid
                          AND position_item.code = 'GROUP_VICE_PRESIDENT'
                        """.formatted(DEMO_TENANT)).containsAll(REQUIRED));
            }
        }
    }

    private Set<String> permissionCodes(Statement statement, String query) throws Exception {
        Set<String> codes = new HashSet<>();
        try (ResultSet result = statement.executeQuery(query)) {
            while (result.next()) codes.add(result.getString(1));
        }
        return codes;
    }
}
