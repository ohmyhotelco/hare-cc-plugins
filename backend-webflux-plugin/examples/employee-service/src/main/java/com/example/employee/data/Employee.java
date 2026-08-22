package com.example.employee.data;

import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.Setter;
import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

@Table("employee")
@Getter
@Setter
public class Employee {

    // Explicit @Column even on the @Id field: Spring Data R2DBC resolves the column
    // name for an unannotated @Id property through a different code path than
    // @Column-annotated properties, and the two can disagree on letter casing against
    // some dialects (observed against H2Dialect). Always annotate every field.
    @Id
    @Column("sequence")
    private Long sequence;

    @Column("id")
    private UUID id;

    @Column("email")
    private String email;

    @Column("display_name")
    private String displayName;

    @Column("created_at")
    private LocalDateTime createdAt;

    @Column("updated_at")
    private LocalDateTime updatedAt;
}
