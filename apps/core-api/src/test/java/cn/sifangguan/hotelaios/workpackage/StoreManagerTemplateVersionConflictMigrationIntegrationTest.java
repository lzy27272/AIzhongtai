package cn.sifangguan.hotelaios.workpackage;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.assertEquals;

class StoreManagerTemplateVersionConflictMigrationIntegrationTest {
    private static final String TENANT = "10000000-0000-0000-0000-000000000001";
    private static final String DEFINITION = "42000000-0000-0000-0000-000000000004";

    @Test
    void migrationsAdvancePastAnExistingTenantDraftVersion() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.builder().start()) {
            DataSource dataSource = postgres.getPostgresDatabase();
            assertEquals(45, migrate(dataSource, "45"));

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                statement.execute("SELECT set_config('app.tenant_id', '" + TENANT + "', false)");
                statement.executeUpdate("""
                        INSERT INTO work_package_version
                            (id, tenant_id, work_package_definition_id, version_no,
                             lifecycle_status, title, description, created_by)
                        VALUES
                            ('dbbc2b39-e986-40f9-91ac-530d6a50e5a1', '%s', '%s', 2,
                             'DRAFT', 'tenant draft', 'pre-existing production draft',
                             '19000000-0000-0000-0000-000000000001')
                        """.formatted(TENANT, DEFINITION));
            }

            assertEquals(2, migrate(dataSource, "47"));

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                statement.execute("SELECT set_config('app.tenant_id', '" + TENANT + "', false)");
                assertEquals("1,2,3,4", scalar(statement, """
                        SELECT string_agg(version_no::text, ',' ORDER BY version_no)
                        FROM work_package_version
                        WHERE tenant_id = '%s'::uuid
                          AND work_package_definition_id = '%s'::uuid
                        """.formatted(TENANT, DEFINITION)));
                assertEquals("3", scalar(statement, """
                        SELECT version_no::text FROM work_package_version
                        WHERE tenant_id = '%s'::uuid
                          AND id = '46030000-0000-0000-0000-000000000001'::uuid
                        """.formatted(TENANT)));
                assertEquals("4:PUBLISHED", scalar(statement, """
                        SELECT version_no::text || ':' || lifecycle_status
                        FROM work_package_version
                        WHERE tenant_id = '%s'::uuid
                          AND id = '47030000-0000-0000-0000-000000000001'::uuid
                        """.formatted(TENANT)));
            }
        }
    }

    private static int migrate(DataSource dataSource, String target) {
        return Flyway.configure()
                .dataSource(dataSource)
                .locations("classpath:db/migration")
                .cleanDisabled(true)
                .target(target)
                .load()
                .migrate()
                .migrationsExecuted;
    }

    private static String scalar(Statement statement, String sql) throws Exception {
        try (ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getString(1);
        }
    }
}
