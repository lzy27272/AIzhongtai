package cn.sifangguan.hotelaios.dailyreports;

import cn.sifangguan.hotelaios.shared.context.TenantContext;
import cn.sifangguan.hotelaios.shared.context.TenantPrincipal;
import cn.sifangguan.hotelaios.shared.db.TenantDatabaseContext;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Projects approved routine work into a still-editable daily report. The projection is
 * fact-only and idempotent: it never marks unreviewed work complete and never overwrites
 * the employee's manually entered "other work" item.
 */
@Service
public class DailyReportRoutineProjectionService {
    private static final String RULE_PROVIDER = "INTERNAL_RULE_ENGINE";

    private final NamedParameterJdbcTemplate jdbc;
    private final TenantDatabaseContext databaseContext;
    private final ObjectMapper objectMapper;

    public DailyReportRoutineProjectionService(
            NamedParameterJdbcTemplate jdbc,
            TenantDatabaseContext databaseContext,
            ObjectMapper objectMapper
    ) {
        this.jdbc = jdbc;
        this.databaseContext = databaseContext;
        this.objectMapper = objectMapper;
    }

    public void projectApprovedWorkRecord(UUID workRecordId) {
        TenantPrincipal principal = prepare();
        List<Map<String, Object>> reports = jdbc.queryForList("""
                select report.id as report_id, report.current_revision_id as revision_id
                from work_record record
                join work_expectation expectation
                  on expectation.tenant_id = record.tenant_id
                 and expectation.id = record.work_expectation_id
                join daily_report report
                  on report.tenant_id = record.tenant_id
                 and report.position_assignment_id = expectation.position_assignment_id
                 and report.business_date = record.business_date
                 and report.report_status = 'DRAFT'
                join daily_report_template_item item
                  on item.tenant_id = report.tenant_id
                 and item.work_package_item_id = record.work_package_item_id
                join daily_report_template_section relation
                  on relation.tenant_id = item.tenant_id
                 and relation.section_version_id = item.section_version_id
                 and relation.template_version_id = report.template_version_id
                where record.tenant_id = :tenantId and record.id = :recordId
                  and record.status = 'APPROVED' and report.current_revision_id is not null
                """, base(principal).addValue("recordId", workRecordId));
        for (Map<String, Object> report : reports) {
            projectReport((UUID) report.get("report_id"), (UUID) report.get("revision_id"));
        }
    }

    public void projectReport(UUID reportId, UUID revisionId) {
        TenantPrincipal principal = prepare();
        List<ProjectableRecord> records = jdbc.query("""
                select distinct on (item.id)
                       item.id as template_item_id, record.id as work_record_id,
                       record.position_assignment_id, record.submitted_by_account_id,
                       record.attempt_no, record.payload::text, record.completion_statement,
                       record.exception_statement, record.next_action, record.content_hash,
                       record.occurred_at, record.reviewed_at, package_item.report_policy::text
                from daily_report report
                join daily_report_revision revision
                  on revision.tenant_id = report.tenant_id
                 and revision.id = :revisionId and revision.report_id = report.id
                 and revision.revision_status = 'DRAFT'
                join daily_report_template_section relation
                  on relation.tenant_id = report.tenant_id
                 and relation.template_version_id = report.template_version_id
                join daily_report_template_item item
                  on item.tenant_id = relation.tenant_id
                 and item.section_version_id = relation.section_version_id
                 and item.work_package_item_id is not null
                join work_package_item package_item
                  on package_item.tenant_id = item.tenant_id
                 and package_item.id = item.work_package_item_id
                join work_record record
                  on record.tenant_id = report.tenant_id
                 and record.business_date = report.business_date
                 and record.work_package_item_id = item.work_package_item_id
                 and record.status = 'APPROVED'
                join work_expectation expectation
                  on expectation.tenant_id = record.tenant_id
                 and expectation.id = record.work_expectation_id
                 and expectation.position_assignment_id = report.position_assignment_id
                where report.tenant_id = :tenantId and report.id = :reportId
                  and report.report_status = 'DRAFT'
                  and coalesce((package_item.report_policy ->> 'dailyReport')::boolean, true)
                order by item.id, record.attempt_no desc, record.reviewed_at desc, record.id
                """, base(principal).addValue("reportId", reportId).addValue("revisionId", revisionId),
                (rs, rowNum) -> new ProjectableRecord(
                        rs.getObject("template_item_id", UUID.class),
                        rs.getObject("work_record_id", UUID.class),
                        rs.getObject("position_assignment_id", UUID.class),
                        rs.getObject("submitted_by_account_id", UUID.class),
                        rs.getInt("attempt_no"), rs.getString("payload"),
                        rs.getString("completion_statement"), rs.getString("exception_statement"),
                        rs.getString("next_action"), rs.getString("content_hash"),
                        rs.getObject("occurred_at", java.time.OffsetDateTime.class),
                        rs.getObject("reviewed_at", java.time.OffsetDateTime.class),
                        rs.getString("report_policy")));
        for (ProjectableRecord record : records) {
            projectRecord(principal, revisionId, record);
        }
        refreshRuleAnalysis(principal, reportId, revisionId);
    }

    private void projectRecord(TenantPrincipal principal, UUID revisionId, ProjectableRecord record) {
        ObjectNode reportPolicy = readObject(record.reportPolicy());
        boolean includeEvidence = reportPolicy.path("includeEvidence").asBoolean(true);
        boolean includeExceptions = reportPolicy.path("includeExceptions").asBoolean(true);
        ObjectNode value = objectMapper.createObjectNode();
        value.put("workRecordId", record.workRecordId().toString());
        value.put("status", "APPROVED");
        value.put("completion", blankToFallback(record.completionStatement(), "已完成"));
        String factLabel = reportPolicy.path("factLabel").asText("").trim();
        if (!factLabel.isBlank()) value.put("factLabel", factLabel);
        if (includeExceptions && !isBlank(record.exceptionStatement())) value.put("exception", record.exceptionStatement());
        if (!isBlank(record.nextAction())) value.put("nextAction", record.nextAction());
        value.set("formData", readObject(record.payload()));
        value.put("reviewedAt", record.reviewedAt().toString());
        boolean exception = includeExceptions && !isBlank(record.exceptionStatement())
                && !"无".equals(record.exceptionStatement().trim());
        int evidenceCount = includeEvidence ? countAttachments(principal, record.workRecordId()) : 0;
        ObjectNode summary = objectMapper.createObjectNode();
        summary.put("sourceType", "WORK_RECORD");
        summary.put("workRecordId", record.workRecordId().toString());
        summary.put("attemptNo", record.attemptNo());
        summary.put("evidenceCount", evidenceCount);
        UUID resultId = jdbc.queryForObject("""
                insert into daily_report_item_result
                    (id, tenant_id, revision_id, template_item_id, result_status, value,
                     system_prefilled, employee_confirmed, exception_flag,
                     exception_statement, source_summary, content_hash)
                values (:id, :tenantId, :revisionId, :templateItemId, :resultStatus,
                        cast(:value as jsonb), true, false, :exception,
                        :exceptionStatement, cast(:sourceSummary as jsonb), :contentHash)
                on conflict (tenant_id, revision_id, template_item_id) do update
                set result_status = excluded.result_status, value = excluded.value,
                    system_prefilled = true, exception_flag = excluded.exception_flag,
                    exception_statement = excluded.exception_statement,
                    source_summary = excluded.source_summary, content_hash = excluded.content_hash,
                    row_version = daily_report_item_result.row_version + 1
                returning id
                """, base(principal).addValue("id", UUID.randomUUID())
                .addValue("revisionId", revisionId).addValue("templateItemId", record.templateItemId())
                .addValue("resultStatus", exception ? "EXCEPTION" : "COMPLETED")
                .addValue("value", value.toString()).addValue("exception", exception)
                .addValue("exceptionStatement", exception ? record.exceptionStatement() : null)
                .addValue("sourceSummary", summary.toString()).addValue("contentHash", record.contentHash()),
                UUID.class);

        ObjectNode source = objectMapper.createObjectNode();
        source.put("status", "APPROVED");
        source.put("attemptNo", record.attemptNo());
        source.set("value", value.deepCopy());
        jdbc.update("""
                insert into daily_report_source_reference
                    (id, tenant_id, revision_id, item_result_id, source_type, source_id,
                     source_version, source_snapshot, content_hash, source_occurred_at,
                     linked_by_account_id)
                select :id, :tenantId, :revisionId, :itemResultId, 'WORK_RECORD', :recordId,
                       :sourceVersion, cast(:sourceSnapshot as jsonb), :contentHash,
                       :occurredAt, :actorId
                where not exists (
                    select 1 from daily_report_source_reference existing
                    where existing.tenant_id = :tenantId and existing.revision_id = :revisionId
                      and existing.source_type = 'WORK_RECORD' and existing.source_id = :recordId
                      and existing.source_version = :sourceVersion
                )
                """, base(principal).addValue("id", UUID.randomUUID()).addValue("revisionId", revisionId)
                .addValue("itemResultId", resultId).addValue("recordId", record.workRecordId())
                .addValue("sourceVersion", "attempt-" + record.attemptNo())
                .addValue("sourceSnapshot", source.toString()).addValue("contentHash", record.contentHash())
                .addValue("occurredAt", record.occurredAt()).addValue("actorId", principal.actorId()));

        if (includeEvidence) {
            jdbc.update("""
                    insert into daily_report_evidence
                        (id, tenant_id, revision_id, item_result_id, evidence_type, object_key,
                         original_name, media_type, size_bytes, sha256, structured_snapshot,
                         scan_status, sensitivity_level, uploaded_by_account_id,
                         uploaded_by_assignment_id)
                    select gen_random_uuid(), attachment.tenant_id, :revisionId, :itemResultId,
                           case when attachment.media_type like 'image/%' then 'IMAGE' else 'DOCUMENT' end,
                           attachment.object_key, attachment.original_name, attachment.media_type,
                           attachment.size_bytes, attachment.sha256,
                           jsonb_build_object(
                               'attachmentId', attachment.id::text,
                               'captureSource', attachment.capture_source,
                               'checkpointCode', attachment.checkpoint_code,
                               'evidenceInstanceKey', attachment.evidence_metadata ->> 'evidenceInstanceKey',
                               'receivedAt', attachment.received_at,
                               'sourceSha256', attachment.source_sha256
                           ), attachment.scan_status, 'INTERNAL',
                           coalesce(:submittedByAccountId, :actorId), :assignmentId
                    from attachment
                    where attachment.tenant_id = :tenantId
                      and attachment.work_record_id = :recordId
                      and attachment.scan_status <> 'REJECTED'
                      and not exists (
                          select 1 from daily_report_evidence existing
                          where existing.tenant_id = attachment.tenant_id
                            and existing.revision_id = :revisionId
                            and existing.object_key = attachment.object_key
                      )
                    """, base(principal).addValue("revisionId", revisionId).addValue("itemResultId", resultId)
                    .addValue("recordId", record.workRecordId())
                    .addValue("submittedByAccountId", record.submittedByAccountId())
                    .addValue("actorId", principal.actorId()).addValue("assignmentId", record.assignmentId()));
        }
    }

    private void refreshRuleAnalysis(TenantPrincipal principal, UUID reportId, UUID revisionId) {
        Map<String, Object> facts = jdbc.queryForMap("""
                select report.hotel_org_unit_id, report.org_unit_id, report.business_date,
                       report.position_assignment_id, report.trace_id,
                       (select count(*) from work_expectation expectation
                        join daily_report_template_item item
                          on item.tenant_id = expectation.tenant_id
                         and item.work_package_item_id = expectation.work_package_item_id
                        join daily_report_template_section relation
                          on relation.tenant_id = item.tenant_id
                         and relation.section_version_id = item.section_version_id
                        where expectation.tenant_id = report.tenant_id
                          and expectation.position_assignment_id = report.position_assignment_id
                          and expectation.business_date = report.business_date
                          and expectation.status <> 'CANCELLED'
                          and relation.template_version_id = report.template_version_id) as expected_count,
                       (select count(*) from daily_report_item_result result
                        where result.tenant_id = report.tenant_id
                          and result.revision_id = :revisionId and result.system_prefilled) as completed_count,
                       (select count(*) from daily_report_item_result result
                        where result.tenant_id = report.tenant_id
                          and result.revision_id = :revisionId and result.exception_flag) as exception_count,
                       (select count(*) from daily_report_evidence evidence
                        where evidence.tenant_id = report.tenant_id
                          and evidence.revision_id = :revisionId
                          and evidence.invalidated_at is null
                          and evidence.scan_status <> 'REJECTED') as evidence_count,
                       (select count(*) from work_expectation expectation
                        join daily_report_template_item item
                          on item.tenant_id = expectation.tenant_id
                         and item.work_package_item_id = expectation.work_package_item_id
                        join daily_report_template_section relation
                          on relation.tenant_id = item.tenant_id
                         and relation.section_version_id = item.section_version_id
                        where expectation.tenant_id = report.tenant_id
                          and expectation.position_assignment_id = report.position_assignment_id
                          and expectation.business_date = report.business_date
                          and expectation.status = 'MISSED'
                          and relation.template_version_id = report.template_version_id) as missed_count
                from daily_report report
                where report.tenant_id = :tenantId and report.id = :reportId
                """, base(principal).addValue("reportId", reportId).addValue("revisionId", revisionId));
        int expected = ((Number) facts.get("expected_count")).intValue();
        int completed = ((Number) facts.get("completed_count")).intValue();
        int exceptions = ((Number) facts.get("exception_count")).intValue();
        int missed = ((Number) facts.get("missed_count")).intValue();
        int evidence = ((Number) facts.get("evidence_count")).intValue();
        String analysis = "规则分析：今日标准日常工作已完成 " + completed + "/" + expected
                + " 项，关联证据 " + evidence + " 份；异常 " + exceptions
                + " 项，逾期 " + missed + " 项。";
        String recommendation = exceptions + missed > 0
                ? "请优先核对异常和逾期事项，确认整改责任人与时限。"
                : completed < expected ? "尚有标准事项未完成或未通过审核，请按截止时间跟进。"
                : "标准事项闭环正常，请补充其他工作后提交日报。";
        jdbc.update("""
                update daily_report_revision
                set narrative = :analysis, row_version = row_version + 1
                where tenant_id = :tenantId and id = :revisionId and revision_status = 'DRAFT'
                  and (narrative is null or narrative like '规则分析：%')
                """, base(principal).addValue("revisionId", revisionId).addValue("analysis", analysis));

        ObjectNode input = objectMapper.createObjectNode();
        input.put("reportId", reportId.toString());
        input.put("revisionId", revisionId.toString());
        input.put("expectedCount", expected);
        input.put("completedCount", completed);
        input.put("exceptionCount", exceptions);
        input.put("missedCount", missed);
        input.put("evidenceCount", evidence);
        String inputHash = sha256(input.toString());
        UUID requestId = jdbc.query("""
                select id from ai_request
                where tenant_id = :tenantId and request_type = 'DAILY_REPORT_ANALYSIS'
                  and provider_code = :provider and input_snapshot ->> 'reportId' = :reportIdText
                order by created_at desc limit 1
                for update
                """, base(principal).addValue("provider", RULE_PROVIDER)
                .addValue("reportIdText", reportId.toString()),
                (rs, rowNum) -> rs.getObject("id", UUID.class)).stream().findFirst().orElse(null);
        if (requestId == null) {
            requestId = UUID.randomUUID();
            jdbc.update("""
                    insert into ai_request
                        (id, tenant_id, request_type, status, hotel_org_unit_id, org_unit_id,
                         business_date, provider_code, model_name, model_version, prompt_version,
                         context_version, input_hash, input_snapshot, sensitivity_level,
                         requested_by_account_id, requested_by_assignment_id, trace_id,
                         correlation_id, completed_at)
                    values (:id, :tenantId, 'DAILY_REPORT_ANALYSIS', 'SUCCEEDED', :hotelId, :orgId,
                            :businessDate, :provider, 'deterministic-summary', '1', 'store-manager-v2',
                            'daily-report-v1', :inputHash, cast(:input as jsonb), 'INTERNAL',
                            :actorId, :assignmentId, :traceId, :correlationId, now())
                    """, base(principal).addValue("id", requestId)
                    .addValue("hotelId", facts.get("hotel_org_unit_id")).addValue("orgId", facts.get("org_unit_id"))
                    .addValue("businessDate", facts.get("business_date")).addValue("provider", RULE_PROVIDER)
                    .addValue("inputHash", inputHash).addValue("input", input.toString())
                    .addValue("actorId", principal.actorId()).addValue("assignmentId", facts.get("position_assignment_id"))
                    .addValue("traceId", facts.get("trace_id")).addValue("correlationId", principal.correlationId()));
        } else {
            jdbc.update("""
                    update ai_request set input_hash = :inputHash, input_snapshot = cast(:input as jsonb),
                        status = 'SUCCEEDED', completed_at = now(), row_version = row_version + 1
                    where tenant_id = :tenantId and id = :id
                    """, base(principal).addValue("id", requestId)
                    .addValue("inputHash", inputHash).addValue("input", input.toString()));
        }
        ObjectNode factSummary = input.deepCopy();
        UUID recommendationId = jdbc.query("""
                select id from ai_recommendation
                where tenant_id = :tenantId and ai_request_id = :requestId and recommendation_no = 1
                """, base(principal).addValue("requestId", requestId),
                (rs, rowNum) -> rs.getObject("id", UUID.class)).stream().findFirst().orElse(null);
        if (recommendationId == null) {
            recommendationId = UUID.randomUUID();
            jdbc.update("""
                    insert into ai_recommendation
                        (id, tenant_id, ai_request_id, recommendation_no, recommendation_type,
                         fact_summary, analysis, recommendation, confidence, applicability_scope,
                         model_name, model_version, prompt_version, context_version)
                    values (:id, :tenantId, :requestId, 1, 'DAILY_REPORT_RULE_ANALYSIS',
                            cast(:facts as jsonb), :analysis, :recommendation, 1.0,
                            jsonb_build_object('reportId', :reportIdText),
                            'deterministic-summary', '1', 'store-manager-v2', 'daily-report-v1')
                    """, base(principal).addValue("id", recommendationId).addValue("requestId", requestId)
                    .addValue("facts", factSummary.toString()).addValue("analysis", analysis)
                    .addValue("recommendation", recommendation).addValue("reportIdText", reportId.toString()));
        } else {
            jdbc.update("""
                    update ai_recommendation
                    set fact_summary = cast(:facts as jsonb), analysis = :analysis,
                        recommendation = :recommendation, generated_at = now()
                    where tenant_id = :tenantId and id = :id
                    """, base(principal).addValue("id", recommendationId)
                    .addValue("facts", factSummary.toString()).addValue("analysis", analysis)
                    .addValue("recommendation", recommendation));
        }
        jdbc.update("""
                insert into ai_recommendation_source
                    (id, tenant_id, recommendation_id, source_type, source_id,
                     source_version, source_snapshot, content_hash)
                select :id, :tenantId, :recommendationId, 'DAILY_REPORT', :reportId,
                       :sourceVersion, cast(:sourceSnapshot as jsonb), :contentHash
                where not exists (
                    select 1 from ai_recommendation_source existing
                    where existing.tenant_id = :tenantId
                      and existing.recommendation_id = :recommendationId
                      and existing.source_type = 'DAILY_REPORT'
                      and existing.source_id = :reportId
                      and existing.source_version = :sourceVersion
                )
                """, base(principal).addValue("id", UUID.randomUUID())
                .addValue("recommendationId", recommendationId).addValue("reportId", reportId)
                .addValue("sourceVersion", revisionId + ":" + inputHash.substring(0, 12))
                .addValue("sourceSnapshot", input.toString()).addValue("contentHash", inputHash));
    }

    private int countAttachments(TenantPrincipal principal, UUID workRecordId) {
        Integer count = jdbc.queryForObject("""
                select count(*) from attachment
                where tenant_id = :tenantId and work_record_id = :recordId
                  and scan_status <> 'REJECTED'
                """, base(principal).addValue("recordId", workRecordId), Integer.class);
        return count == null ? 0 : count;
    }

    private ObjectNode readObject(String json) {
        try {
            return (ObjectNode) objectMapper.readTree(json);
        } catch (Exception exception) {
            throw new IllegalArgumentException("工作记录内容不是有效JSON对象", exception);
        }
    }

    private TenantPrincipal prepare() {
        TenantPrincipal principal = TenantContext.require();
        databaseContext.apply(principal.tenantId());
        return principal;
    }

    private MapSqlParameterSource base(TenantPrincipal principal) {
        return new MapSqlParameterSource("tenantId", principal.tenantId());
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    private static String blankToFallback(String value, String fallback) {
        return isBlank(value) ? fallback : value.trim();
    }

    private static String sha256(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException("无法生成规则分析摘要", exception);
        }
    }

    private record ProjectableRecord(
            UUID templateItemId,
            UUID workRecordId,
            UUID assignmentId,
            UUID submittedByAccountId,
            int attemptNo,
            String payload,
            String completionStatement,
            String exceptionStatement,
            String nextAction,
            String contentHash,
            java.time.OffsetDateTime occurredAt,
            java.time.OffsetDateTime reviewedAt,
            String reportPolicy
    ) {
    }
}
