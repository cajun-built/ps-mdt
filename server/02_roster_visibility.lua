CGNMdtRosterVisibility = {}

function CGNMdtRosterVisibility.project(personnel, sameAgency, canManage)
    personnel = personnel or {}
    return {
        certifications = sameAgency and (personnel.certifications or {}) or {},
        employmentStatus = sameAgency and personnel.status or nil,
        assignments = sameAgency and (personnel.assignments or {}) or {},
        primaryAssignment = sameAgency and personnel.primaryAssignment or nil,
        compartments = canManage and (personnel.compartments or {}) or {},
    }
end
